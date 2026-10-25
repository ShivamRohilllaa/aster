import Foundation
import Darwin
import CryptoKit

public struct TrashPolicy: Sendable {
    /// An optional additional scope restriction, primarily useful for isolated tests.
    /// It never overrides system-path or symlink protections.
    public let allowedRoots: [URL]
    public let maxItems: Int
    public let previewLifetime: TimeInterval
    public let homeDirectory: URL

    public init(allowedRoots: [URL] = [], maxItems: Int = 100_000, previewLifetime: TimeInterval = 900, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.allowedRoots = allowedRoots
        self.maxItems = max(1, maxItems)
        self.previewLifetime = max(1, previewLifetime)
        self.homeDirectory = homeDirectory
    }
}

public struct TrashPreviewItem: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let logicalSize: Int64
    public let fileCount: Int
    public let blockedReason: String?
    public let warnings: [String]
    public var canMove: Bool { blockedReason == nil }
    fileprivate let fingerprint: TrashFingerprint?
}

public struct TrashPreview: Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let items: [TrashPreviewItem]
    public let isCancelled: Bool
    fileprivate let serviceID: UUID
}

public enum TrashItemStatus: String, Sendable {
    case moved, failed, skipped
}

public struct TrashItemResult: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let status: TrashItemStatus
    public let trashURL: URL?
    public let message: String
    public let logicalSize: Int64
}

public struct TrashReport: Sendable {
    public let results: [TrashItemResult]
    public let wasCancelled: Bool
    public let previewAlreadyUsed: Bool
}

fileprivate struct TrashFingerprint: Sendable, Equatable {
    let digest: Data
    let root: TrashMetadata
}

fileprivate struct TrashMetadata: Sendable, Equatable {
    let device: Int64
    let inode: UInt64
    let mode: UInt16
    let size: Int64
    let links: UInt16
    let modifiedSeconds: Int64
    let modifiedNanos: Int64
    let changedSeconds: Int64
    let changedNanos: Int64
    let bornSeconds: Int64
    let bornNanos: Int64
    let blocks: Int64

    var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    var isLink: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFLNK) }
    var isFile: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    var signature: String {
        "\(device):\(inode):\(mode):\(size):\(links):\(modifiedSeconds):\(modifiedNanos):\(changedSeconds):\(changedNanos):\(bornSeconds):\(bornNanos):\(blocks)"
    }
}

/// Previews and moves selected filesystem entries to the macOS Trash. No method
/// permanently deletes an item or falls back to removeItem when Trash fails.
/// A preview belongs to one service, expires, and can be submitted only once.
public actor TrashService {
    public typealias Mover = @Sendable (URL) throws -> URL?

    private let policy: TrashPolicy
    private let mover: Mover
    private let serviceID = UUID()
    private var usedPreviews: [UUID: Date] = [:]
    private var isMoving = false

    public init(policy: TrashPolicy = .init(), mover: Mover? = nil) {
        self.policy = policy
        self.mover = mover ?? { url in
            var destination: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
            return destination as URL?
        }
    }

    public func prepare(urls: [URL], protectedURLs: [URL] = []) async -> TrashPreview {
        let policy = policy
        let serviceID = serviceID
        let worker = Task.detached(priority: .userInitiated) {
            Self.prepareSynchronously(urls: urls, protectedURLs: protectedURLs, policy: policy, serviceID: serviceID)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    public func moveToTrash(preview: TrashPreview, confirmedIDs: Set<String>, protectedURLs: [URL] = [], dependencies: [String: String] = [:]) async -> TrashReport {
        let now = Date()
        let policy = self.policy
        usedPreviews = usedPreviews.filter { now.timeIntervalSince($0.value) <= policy.previewLifetime }
        let alreadyUsed = usedPreviews[preview.id] != nil
        let invalidReason: String?
        if preview.serviceID != serviceID {
            invalidReason = "This preview belongs to another cleanup session. Review these items again."
        } else if alreadyUsed {
            invalidReason = "This preview has already been submitted. Review remaining items again."
        } else if isMoving {
            invalidReason = "Another cleanup is in progress. Wait for it to finish before moving these items."
        } else if preview.isCancelled || Task.isCancelled {
            invalidReason = "Cleanup was cancelled. No additional items were moved."
        } else if now.timeIntervalSince(preview.createdAt) > policy.previewLifetime || preview.createdAt > now {
            invalidReason = "This preview expired. Review these items again."
        } else if !confirmedIDs.isSubset(of: Set(preview.items.map(\.id))) {
            invalidReason = "The confirmation contains an item outside this preview. Review these items again."
        } else {
            invalidReason = nil
        }
        if let invalidReason {
            return TrashReport(results: preview.items.map { Self.result($0, .skipped, invalidReason) }, wasCancelled: Task.isCancelled || preview.isCancelled, previewAlreadyUsed: alreadyUsed)
        }
        // Mark before the first await so concurrent calls cannot reuse a preview.
        usedPreviews[preview.id] = preview.createdAt
        isMoving = true
        defer { isMoving = false }
        let mover = mover
        let worker = Task.detached(priority: .userInitiated) {
            Self.moveSynchronously(preview: preview, confirmedIDs: confirmedIDs, protectedURLs: protectedURLs, dependencies: dependencies, policy: policy, mover: mover)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func prepareSynchronously(urls: [URL], protectedURLs: [URL], policy: TrashPolicy, serviceID: UUID) -> TrashPreview {
        let createdAt = Date()
        var budget = policy.maxItems
        var selected: [URL] = []
        var seen = Set<String>()
        for url in urls {
            let id = itemID(url)
            if seen.insert(id).inserted { selected.append(url) }
        }
        // A selected directory owns its descendants. Keep blocked parents visible
        // instead of silently turning a blocked selection into a narrower action.
        let roots = selected.filter { child in
            !selected.contains { parent in
                parent != child && parent.isFileURL && child.isFileURL && contains(parent.path, child.path) && parent.path != child.path
            }
        }
        var items: [TrashPreviewItem] = []
        for url in roots {
            if Task.isCancelled {
                items.append(TrashPreviewItem(id: itemID(url), url: url, logicalSize: 0, fileCount: 0, blockedReason: "Preview cancelled. Review these items again.", warnings: [], fingerprint: nil))
                continue
            }
            var warnings: [String] = []
            let nested = selected.filter { $0 != url && $0.isFileURL && url.isFileURL && contains(url.path, $0.path) }.count
            if nested > 0 { warnings.append("Includes \(nested) nested selection\(nested == 1 ? "" : "s"); each item will be moved only once.") }
            do {
                try validate(url, protectedURLs: protectedURLs, policy: policy)
                let measured = try measure(url, remainingBudget: &budget)
                if measured.linkCount > 0 { warnings.append("Contains \(measured.linkCount) symbolic link\(measured.linkCount == 1 ? "" : "s"). Only the links are moved; their targets are not followed.") }
                warnings.append("Moving to Trash does not immediately recover disk space.")
                items.append(TrashPreviewItem(id: itemID(url), url: url, logicalSize: measured.bytes, fileCount: measured.files, blockedReason: nil, warnings: warnings, fingerprint: measured.fingerprint))
            } catch {
                items.append(TrashPreviewItem(id: itemID(url), url: url, logicalSize: 0, fileCount: 0, blockedReason: error.localizedDescription, warnings: warnings, fingerprint: nil))
            }
        }
        return TrashPreview(id: UUID(), createdAt: createdAt, items: items, isCancelled: Task.isCancelled, serviceID: serviceID)
    }

    private static func moveSynchronously(preview: TrashPreview, confirmedIDs: Set<String>, protectedURLs: [URL], dependencies: [String: String], policy: TrashPolicy, mover: Mover) -> TrashReport {
        var results: [TrashItemResult] = []
        var statuses: [String: TrashItemStatus] = [:]
        var budget = policy.maxItems
        var wasCancelled = false
        let ordered = dependencyOrder(items: preview.items, confirmedIDs: confirmedIDs, dependencies: dependencies)
        for item in ordered.items {
            defer { statuses[item.id] = results.last?.status }
            if Task.isCancelled {
                wasCancelled = true
                results.append(result(item, .skipped, "Cleanup cancelled. This item was not moved."))
                continue
            }
            guard confirmedIDs.contains(item.id) else {
                results.append(result(item, .skipped, "This item was not confirmed."))
                continue
            }
            if let blocked = ordered.blocked[item.id] {
                results.append(result(item, .skipped, blocked))
                continue
            }
            if let prerequisite = dependencies[item.id], statuses[prerequisite] != .moved {
                results.append(result(item, .skipped, "The related application was not successfully moved to Trash. Its data was kept."))
                continue
            }
            guard item.canMove, let original = item.fingerprint else {
                results.append(result(item, .skipped, item.blockedReason ?? "No complete preview is available."))
                continue
            }
            if Task.isCancelled {
                wasCancelled = true
                results.append(result(item, .skipped, "Cleanup cancelled. This item was not moved."))
                continue
            }
            do {
                try validate(item.url, protectedURLs: protectedURLs, policy: policy)
                let current = try measure(item.url, remainingBudget: &budget)
                guard original == current.fingerprint else {
                    results.append(result(item, .skipped, "This item or its contents changed after review. Prepare a fresh preview."))
                    continue
                }
                try Task.checkCancellation()
                // Check ancestors again immediately before the URL-based macOS
                // operation. Filesystems do not provide a lock across this call.
                try validateAncestors(item.url)
                guard try metadata(item.url) == original.root else {
                    results.append(result(item, .skipped, "This item changed after review. Prepare a fresh preview."))
                    continue
                }
            } catch is CancellationError {
                wasCancelled = true
                results.append(result(item, .skipped, "Cleanup cancelled. This item was not moved."))
                continue
            } catch {
                results.append(result(item, .skipped, "Could not revalidate this item: \(error.localizedDescription)"))
                continue
            }
            if Task.isCancelled {
                wasCancelled = true
                results.append(result(item, .skipped, "Cleanup cancelled. This item was not moved."))
                continue
            }
            do {
                let destination = try mover(item.url)
                results.append(TrashItemResult(id: item.id, url: item.url, status: .moved, trashURL: destination, message: "Moved to Trash. Disk space has not been counted as recovered.", logicalSize: item.logicalSize))
            } catch {
                results.append(result(item, .failed, "macOS could not move this item to Trash: \(error.localizedDescription)"))
            }
        }
        return TrashReport(results: results, wasCancelled: wasCancelled || Task.isCancelled, previewAlreadyUsed: false)
    }

    private static func dependencyOrder(items: [TrashPreviewItem], confirmedIDs: Set<String>, dependencies: [String: String]) -> (items: [TrashPreviewItem], blocked: [String: String]) {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var blocked: [String: String] = [:]
        var indegree = Dictionary(uniqueKeysWithValues: items.map { ($0.id, 0) })
        var children: [String: [String]] = [:]
        for item in items {
            guard let prerequisite = dependencies[item.id] else { continue }
            guard byID[prerequisite] != nil, confirmedIDs.contains(prerequisite) else {
                blocked[item.id] = "The related application's removal was not confirmed in this preview. Its data was kept."
                continue
            }
            indegree[item.id] = 1
            children[prerequisite, default: []].append(item.id)
        }
        var queue = items.filter { indegree[$0.id] == 0 }.map(\.id)
        var index = 0
        while index < queue.count {
            let id = queue[index]
            index += 1
            for child in children[id, default: []] {
                indegree[child, default: 0] -= 1
                if indegree[child] == 0 { queue.append(child) }
            }
        }
        for item in items where indegree[item.id, default: 0] > 0 {
            blocked[item.id] = "This selection contains a dependency cycle. Review these items again."
            queue.append(item.id)
        }
        return (queue.compactMap { byID[$0] }, blocked)
    }

    private struct Measurement {
        let bytes: Int64
        let files: Int
        let linkCount: Int
        let fingerprint: TrashFingerprint
    }

    private static func measure(_ root: URL, remainingBudget: inout Int) throws -> Measurement {
        try Task.checkCancellation()
        var entries: [(String, TrashMetadata)] = []
        var bytes: Int64 = 0
        var files = 0
        var linkCount = 0
        let original = try metadata(root)
        func append(_ relativePath: String, _ value: TrashMetadata) throws {
            guard remainingBudget > 0 else { throw TrashFailure("The review reached its item limit. Select fewer or smaller folders.") }
            remainingBudget -= 1
            entries.append((relativePath, value))
            if value.isFile {
                let sum = bytes.addingReportingOverflow(max(0, value.size))
                guard !sum.overflow else { throw TrashFailure("The reported file size is too large to review safely.") }
                bytes = sum.partialValue
                files += 1
            } else if value.isLink {
                linkCount += 1
            } else if !value.isDirectory {
                throw TrashFailure("This selection contains a special filesystem entry that cannot be reviewed safely.")
            }
        }
        try append("", original)
        if original.isDirectory {
            var enumerationError: Error?
            guard let enumerator = FileManager().enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in
                enumerationError = error
                return false
            }) else { throw TrashFailure("The folder could not be read completely.") }
            while let item = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if let enumerationError { throw enumerationError }
                let relativePath = item.pathComponents.suffix(enumerator.level).joined(separator: "/")
                let url = root.appendingPathComponent(relativePath)
                try validateAncestors(url.deletingLastPathComponent())
                let value = try metadata(url)
                guard value.device == original.device else { throw TrashFailure("This folder contains a mounted volume. Review that volume separately.") }
                try append(relativePath, value)
                // Foundation does not descend through symlinks. Calling
                // skipDescendants on a link can skip an unrelated next folder.
            }
            if let enumerationError { throw enumerationError }
        }
        try Task.checkCancellation()
        guard try metadata(root) == original else { throw TrashFailure("This item changed during review. Prepare a fresh preview.") }
        var digest = SHA256()
        for (path, value) in entries.sorted(by: { $0.0 < $1.0 }) {
            digest.update(data: Data(path.utf8))
            digest.update(data: Data([0]))
            digest.update(data: Data(value.signature.utf8))
            digest.update(data: Data([0]))
        }
        return Measurement(bytes: bytes, files: files, linkCount: linkCount, fingerprint: TrashFingerprint(digest: Data(digest.finalize()), root: original))
    }

    private static func validate(_ url: URL, protectedURLs: [URL], policy: TrashPolicy) throws {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost", url.path.hasPrefix("/") else {
            throw TrashFailure("Only local files and folders can be moved to Trash.")
        }
        let path = url.path
        let components = url.pathComponents
        guard !components.contains(".."), !components.contains(".") else { throw TrashFailure("Choose the original item instead of a path containing relative components.") }
        try validateAncestors(url)
        let value = try metadata(url)
        guard !value.isLink else { throw TrashFailure("Symbolic links cannot be selected for cleanup. Choose and review the original item directly.") }
        guard value.isFile || value.isDirectory else { throw TrashFailure("This filesystem entry cannot be moved safely.") }

        let protectedTrees = ["/System", "/bin", "/sbin", "/usr", "/etc", "/private/etc", "/private/var", "/dev", "/cores", "/Library", "/Network"]
        let protectedRoots = ["/", "/Applications", "/Applications/Utilities", "/Users", "/Volumes", "/private", "/private/tmp", "/tmp"]
        guard !protectedRoots.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }), !protectedTrees.contains(where: { protectedContains($0, path) }), !(components.count == 3 && components[1].lowercased() == "users") else {
            throw TrashFailure("System locations and shared application roots are protected.")
        }
        guard !components.contains(where: { [".trash", ".trashes", ".documentrevisions-v100", ".spotlight-v100", ".fseventsd"].contains($0.lowercased()) }) else {
            throw TrashFailure("Trash and macOS-managed storage cannot be selected for cleanup.")
        }
        let home = policy.homeDirectory.path
        let homeRoots = [home, home + "/Library", home + "/Applications"] + ["Application Support", "Caches", "Developer", "Preferences", "Containers", "Logs", "WebKit", "HTTPStorages", "Saved Application State"].map { home + "/Library/" + $0 }
        let homeTrees = ["Group Containers", "Keychains", "Mail", "Messages", "Safari"].map { home + "/Library/" + $0 }
        guard !homeRoots.contains(where: { $0.caseInsensitiveCompare(path) == .orderedSame }), !homeTrees.contains(where: { protectedContains($0, path) }) else {
            throw TrashFailure("Your home folder and essential application-data locations are protected.")
        }
        let containers = home + "/Library/Containers"
        if protectedContains(containers, path) {
            let identifier = String(path.dropFirst(containers.count + 1))
            guard validIdentifier(identifier), !protectedIdentifier(identifier) else {
                throw TrashFailure("Only a complete, explicitly reviewed third-party application container can be selected.")
            }
        }
        let applicationDataRoots = ["Application Support", "Caches", "Preferences", "Logs", "WebKit", "HTTPStorages", "Saved Application State"].map { home + "/Library/" + $0 }
        for dataRoot in applicationDataRoots where protectedContains(dataRoot, path) {
            let owner = path.dropFirst(dataRoot.count + 1).split(separator: "/").first.map(String.init) ?? ""
            if protectedIdentifier(owner) { throw TrashFailure("Apple application data is protected from cleanup.") }
        }
        for protected in protectedURLs where protected.isFileURL {
            if protectedContains(protected.path, path) || protectedContains(path, protected.path) {
                throw TrashFailure("This item contains, or belongs to, a protected or running application.")
            }
        }
        if !policy.allowedRoots.isEmpty {
            guard policy.allowedRoots.contains(where: { $0.isFileURL && $0.path != path && contains($0.path, path) }) else {
                throw TrashFailure("This item is outside the permitted cleanup folders.")
            }
        }
        if value.isDirectory, path != "/" {
            let parent = try metadata(url.deletingLastPathComponent())
            guard parent.device == value.device else { throw TrashFailure("A mounted volume cannot be moved to Trash.") }
        }
        // Reverse-DNS data directories such as com.example.app are not bundles.
        let isApplicationDataPath = ([containers] + applicationDataRoots).contains { protectedContains($0, path) }
        if !isApplicationDataPath, let appIndex = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) {
            guard appIndex == components.count - 1 else { throw TrashFailure("Select the complete application bundle instead of one of its internal files.") }
            let infoURL = url.appendingPathComponent("Contents/Info.plist")
            try validateAncestors(infoURL)
            let info = try metadata(infoURL)
            guard info.isFile, info.size < 2_000_000 else { throw TrashFailure("This application's identity could not be verified.") }
            let data = try Data(contentsOf: infoURL, options: [.mappedIfSafe])
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let identifier = plist["CFBundleIdentifier"] as? String, !identifier.isEmpty else {
                throw TrashFailure("This application's identity could not be verified.")
            }
            guard !protectedIdentifier(identifier) else { throw TrashFailure("Apple applications are protected from cleanup.") }
        } else if protectedContains("/Applications", path) {
            throw TrashFailure("Only complete third-party application bundles can be selected inside Applications.")
        }
    }

    private static func validateAncestors(_ url: URL) throws {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            if try metadata(current).isLink {
                throw TrashFailure("This path passes through a symbolic link. Choose the original location directly.")
            }
        }
    }

    private static func metadata(_ url: URL) throws -> TrashMetadata {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.lstat(path, &info)
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path]) }
        return TrashMetadata(device: Int64(info.st_dev), inode: UInt64(info.st_ino), mode: UInt16(info.st_mode), size: Int64(info.st_size), links: UInt16(info.st_nlink), modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec), changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanos: Int64(info.st_ctimespec.tv_nsec), bornSeconds: Int64(info.st_birthtimespec.tv_sec), bornNanos: Int64(info.st_birthtimespec.tv_nsec), blocks: Int64(info.st_blocks))
    }

    private static func contains(_ parent: String, _ child: String) -> Bool {
        parent == child || (parent == "/" ? child.hasPrefix("/") : child.hasPrefix(parent + "/"))
    }

    /// Conservative case-insensitive protection also covers alternate spelling
    /// on the case-insensitive volumes used by most Macs.
    private static func protectedContains(_ parent: String, _ child: String) -> Bool {
        contains(parent.lowercased(), child.lowercased())
    }

    private static func validIdentifier(_ value: String) -> Bool {
        guard value.count <= 255, !value.isEmpty else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let valid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return parts.allSatisfy { part in
            guard let first = part.unicodeScalars.first, letters.contains(first), !part.hasSuffix("-") else { return false }
            return part.unicodeScalars.allSatisfy(valid.contains)
        }
    }

    private static func protectedIdentifier(_ value: String) -> Bool {
        let identifier = value.lowercased()
        return identifier == "com.apple" || identifier.hasPrefix("com.apple.")
    }

    private static func itemID(_ url: URL) -> String { url.isFileURL ? url.path : url.absoluteString }

    private static func result(_ item: TrashPreviewItem, _ status: TrashItemStatus, _ message: String) -> TrashItemResult {
        TrashItemResult(id: item.id, url: item.url, status: status, trashURL: nil, message: message, logicalSize: item.logicalSize)
    }
}

private struct TrashFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
