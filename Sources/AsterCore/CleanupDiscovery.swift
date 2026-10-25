import Foundation
import Darwin

public enum CleanupArea: String, CaseIterable, Sendable {
    case caches, logs, developer

    public var title: String {
        switch self {
        case .caches: return "Caches"
        case .logs: return "Logs"
        case .developer: return "Developer"
        }
    }

    public var relativePath: String {
        switch self {
        case .caches: return "Library/Caches"
        case .logs: return "Library/Logs"
        case .developer: return "Library/Developer/Xcode/DerivedData"
        }
    }

    public func location(in home: URL) -> URL {
        home.absoluteURL.appendingPathComponent(relativePath, isDirectory: true)
    }
}

/// A measured direct child of a supported user cache/log location. It remains
/// a review suggestion, not a statement that its contents are unnecessary.
public struct CleanupDiscoveryEntry: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let area: CleanupArea
    public let logicalSize: Int64
    public let fileCount: Int
    public let isPartial: Bool
    public let ownerBundleIdentifier: String?
    public let blockedReason: String?
    public let note: String
    public let documentationURL: URL?

    public init(url: URL, title: String, area: CleanupArea, logicalSize: Int64, fileCount: Int, isPartial: Bool = false, ownerBundleIdentifier: String? = nil, blockedReason: String? = nil, note: String = "", documentationURL: URL? = nil) {
        self.url = url
        self.title = title
        self.area = area
        self.logicalSize = logicalSize
        self.fileCount = fileCount
        self.isPartial = isPartial
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.blockedReason = blockedReason
        self.note = note
        self.documentationURL = documentationURL
    }
}

public struct CleanupDiscoveryResult: Sendable {
    public let entries: [CleanupDiscoveryEntry]
    public let warnings: [String]
    public let isComplete: Bool

    public init(entries: [CleanupDiscoveryEntry], warnings: [String] = [], isComplete: Bool = true) {
        self.entries = entries
        self.warnings = warnings
        self.isComplete = isComplete
    }
}

/// Metadata-only discovery limited to the current user's Caches, Logs, and
/// Xcode DerivedData and documented tool-cache locations. It neither opens
/// file contents nor removes anything.
public enum CleanupDiscoveryScanner {
    public static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, maxNodesPerRoot: Int = 100_000, maxEntriesPerRoot: Int = 2_000) async throws -> CleanupDiscoveryResult {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try await scanRoots(home: home.absoluteURL, maxNodesPerRoot: maxNodesPerRoot, maxEntriesPerRoot: maxEntriesPerRoot)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private static func scanRoots(home: URL, maxNodesPerRoot: Int, maxEntriesPerRoot: Int) async throws -> CleanupDiscoveryResult {
        guard home.isFileURL else {
            return CleanupDiscoveryResult(entries: [], warnings: ["Choose a home folder on this Mac."], isComplete: false)
        }
        do {
            try verifyDirectoryPath(home)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return CleanupDiscoveryResult(entries: [], warnings: ["Could not inspect the home folder at \(home.path): \(error.localizedDescription)"], isComplete: false)
        }

        var entries: [CleanupDiscoveryEntry] = []
        var warnings: [String] = []
        var isComplete = true
        var measured = Set<String>()

        func measure(_ url: URL, title: String, area: CleanupArea, ownerBundleIdentifier: String? = nil, note: String = "", vendorManaged: Bool = false, documentationURL: URL? = nil) async throws {
            try Task.checkCancellation()
            guard measured.insert(url.path).inserted else { return }
            do {
                let snapshot = try await DiskScanner(maxNodeCount: maxNodesPerRoot, maxIssueCount: 40).scan(url: url) { _ in }
                try Task.checkCancellation()
                let node = snapshot.root
                // DiskScanner never follows links; their targets are outside
                // the measured tree and do not make regular contents partial.
                guard !node.isSymbolicLink else { return }
                if snapshot.isPartial { isComplete = false }
                for issue in snapshot.issues {
                    warnings.append("\(area.title): \(issue.path) — \(issue.message)")
                }
                let appleOwned = node.name.lowercased() == "com.apple" || node.name.lowercased().hasPrefix("com.apple.")
                let blocked: String?
                if snapshot.isPartial {
                    blocked = "This item was only partially scanned. Its size is incomplete, so cleanup is disabled until a complete scan succeeds."
                } else if vendorManaged {
                    blocked = "Use this tool’s own cleanup controls. This location is shown for visibility and cannot be added to Aster’s cleanup queue."
                } else if appleOwned {
                    blocked = "Apple application data is shown for visibility and protected from cleanup."
                } else {
                    blocked = nil
                }
                entries.append(CleanupDiscoveryEntry(url: node.url, title: title, area: area,
                    logicalSize: node.logicalSize, fileCount: node.fileCount,
                    isPartial: snapshot.isPartial, ownerBundleIdentifier: ownerBundleIdentifier ?? possibleOwner(of: node),
                    blockedReason: blocked, note: note, documentationURL: documentationURL))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                isComplete = false
                warnings.append("Could not measure \(title) at \(url.path): \(error.localizedDescription)")
                entries.append(CleanupDiscoveryEntry(url: url, title: title, area: area,
                    logicalSize: 0, fileCount: 0, isPartial: true, ownerBundleIdentifier: ownerBundleIdentifier,
                    blockedReason: "This item could not be measured. Cleanup is disabled until a complete scan succeeds.",
                    note: note, documentationURL: documentationURL))
            }
        }

        // Generic locations expose their direct children, never the whole
        // Library/Caches or Library/Logs root. Each child's tree is measured
        // separately so a large or unreadable item does not block its neighbors.
        for area in CleanupArea.allCases {
            try Task.checkCancellation()
            let root = area.location(in: home)
            do {
                try verifyDirectoryPath(root)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isMissing(error) { continue }
                isComplete = false
                warnings.append("Could not inspect \(area.title) at \(root.path): \(error.localizedDescription)")
                continue
            }

            guard let enumerator = FileManager().enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants], errorHandler: { url, error in
                    isComplete = false
                    warnings.append("Could not list \(area.title) at \(url.path): \(error.localizedDescription)")
                    return false
                }) else {
                isComplete = false
                warnings.append("Could not list \(area.title) at \(root.path).")
                continue
            }
            var count = 0
            while let item = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                count += 1
                if count > max(1, maxEntriesPerRoot) {
                    isComplete = false
                    warnings.append("\(area.title) reached its \(max(1, maxEntriesPerRoot).formatted())-entry listing limit. Some locations were not measured.")
                    break
                }
                let child = root.appendingPathComponent(item.lastPathComponent)
                do {
                    let type = try metadata(child).st_mode & mode_t(S_IFMT)
                    guard type == S_IFDIR || type == S_IFREG else { continue }
                } catch {
                    isComplete = false
                    warnings.append("Could not inspect \(child.path): \(error.localizedDescription)")
                    continue
                }
                let descriptor = DeveloperCacheLocations.all.first { $0.relativeHomePath == area.relativePath }
                try await measure(child, title: child.lastPathComponent, area: area,
                                  ownerBundleIdentifier: area == .developer ? "com.apple.dt.Xcode" : nil,
                                  note: descriptor?.note ?? "",
                                  vendorManaged: descriptor?.cleanupPolicy == .vendorManaged,
                                  documentationURL: descriptor?.documentationURL)
            }
        }

        // Additional tool roots have precise documented boundaries. Measure
        // each whole cache as one row instead of exposing opaque hash buckets.
        for location in DeveloperCacheLocations.all {
            try Task.checkCancellation()
            // Xcode DerivedData is already represented by its project children.
            // Adding the parent would overlap those rows and double-count bytes.
            guard !CleanupArea.allCases.contains(where: { $0.relativePath == location.relativeHomePath }) else { continue }
            let root = home.appendingPathComponent(location.relativeHomePath, isDirectory: true)
            do {
                try verifyDirectoryPath(root)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isMissing(error) { continue }
                isComplete = false
                warnings.append("Could not inspect \(location.title) at \(root.path): \(error.localizedDescription)")
                continue
            }
            try await measure(root, title: location.title, area: .developer, note: location.note,
                              vendorManaged: location.cleanupPolicy == .vendorManaged,
                              documentationURL: location.documentationURL)
        }
        try Task.checkCancellation()
        entries.sort {
            if $0.logicalSize != $1.logicalSize { return $0.logicalSize > $1.logicalSize }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        return CleanupDiscoveryResult(entries: entries, warnings: warnings, isComplete: isComplete)
    }

    private static func possibleOwner(of node: DiskNode) -> String? {
        // Only a complete reverse-DNS-like direct-child name is used. Generic
        // names and project names are not fuzzy-matched to installed apps.
        let value = !node.isDirectory && node.url.pathExtension.lowercased() == "log"
            ? node.url.deletingPathExtension().lastPathComponent : node.name
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, value.count <= 255 else { return nil }
        let initial = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let characters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard parts.allSatisfy({ part in
            guard let first = part.unicodeScalars.first, initial.contains(first) else { return false }
            return part.unicodeScalars.allSatisfy(characters.contains)
        }) else { return nil }
        return value
    }

    private static func verifyDirectoryPath(_ url: URL) throws {
        var componentURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents where component != "/" {
            try Task.checkCancellation()
            componentURL.appendPathComponent(component)
            let info = try metadata(componentURL)
            let type = info.st_mode & mode_t(S_IFMT)
            guard type == S_IFDIR else {
                let detail = type == S_IFLNK ? "Symbolic-link locations are excluded" : "The location is not a directory"
                throw NSError(domain: "AsterCleanupDiscovery", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(detail): \(componentURL.path)"])
            }
        }
    }

    private static func metadata(_ url: URL) throws -> stat {
        var value = stat()
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &value)
        }
        guard status == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        return value
    }

    private static func isMissing(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == NSPOSIXErrorDomain && value.code == Int(ENOENT)
    }
}
