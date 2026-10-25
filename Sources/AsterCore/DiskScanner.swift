import Foundation
import Darwin

/// Reads filesystem metadata only. It never opens file contents or mutates files.
/// Values are a best-effort point-in-time view; macOS snapshots, APFS clones,
/// compression, directory metadata and purgeable space cannot be reconciled with
/// the volume's reported used space using per-file metadata alone.
public struct DiskScanner: Sendable {
    public let maxNodeCount: Int
    public let maxIssueCount: Int

    public init(maxNodeCount: Int = 250_000, maxIssueCount: Int = 100) {
        self.maxNodeCount = max(1, maxNodeCount)
        self.maxIssueCount = max(1, maxIssueCount)
    }

    /// All enumeration and aggregation run in an unstructured background task;
    /// cancellation is explicitly forwarded from the calling task.
    public func scan(url: URL, progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> DiskSnapshot {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try scanSynchronously(url: url, progress: progress)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private struct Inode: Hashable {
        let device: dev_t
        let number: ino_t
    }

    private func scanSynchronously(url: URL, progress: @Sendable (ScanProgress) -> Void) throws -> DiskSnapshot {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ScanError.notAFileURL }
        let startedAt = Date()
        // Keep one spelling of the selected root. Foundation can canonicalize
        // /private/var differently for existing and dangling-link URLs.
        let rootURL = url.absoluteURL
        let rootID = rootURL.path
        let rootMetadata = try metadata(at: rootURL)
        var allocatedInodes = Set<Inode>()
        var root = makeNode(url: rootURL, metadata: rootMetadata, parentID: nil, allocatedInodes: &allocatedInodes)
        if rootID == "/" { root.name = "Macintosh HD" }
        var nodes = [rootID: root]
        var order = [rootID]
        var issues: [ScanIssue] = []
        var isPartial = false
        var visitedFileCount = root.fileCount
        var logicalBytes = root.logicalSize
        var skippedLinkCount = root.isSymbolicLink ? 1 : 0
        var lastProgress = Date.distantPast

        func recordIssue(path: String, message: String) {
            isPartial = true
            if issues.count < maxIssueCount {
                issues.append(ScanIssue(path: path, message: message))
            }
        }

        progress(ScanProgress(fileCount: visitedFileCount, itemCount: 1, logicalBytes: logicalBytes, currentPath: rootID))
        if root.isDirectory {
            let manager = FileManager()
            guard let enumerator = manager.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: [], errorHandler: { failingURL, error in
                recordIssue(path: failingURL.path, message: error.localizedDescription)
                return !Task.isCancelled
            }) else {
                throw ScanError.cannotEnumerate(rootID)
            }

            while let item = enumerator.nextObject() as? URL {
                try Task.checkCancellation()
                if nodes.count >= maxNodeCount {
                    recordIssue(path: rootID, message: "The scan reached its \(maxNodeCount.formatted())-item memory limit. Scan a smaller folder to explore the remaining files.")
                    break
                }
                // The enumerator may return /private/var URLs for a /var root.
                // Its level gives the exact relative suffix, including dangling
                // symlinks, without resolving or changing any link's identity.
                let relativePath = item.pathComponents.suffix(enumerator.level).joined(separator: "/")
                let itemURL = rootURL.appendingPathComponent(relativePath, isDirectory: item.hasDirectoryPath)
                let path = itemURL.path

                // APFS exposes Data and other mounted volumes here as aliases of
                // paths already reachable at /. Avoid inflated root-disk totals.
                if rootID == "/" && (path == "/System/Volumes" || path == "/Volumes") {
                    enumerator.skipDescendants()
                    recordIssue(path: path, message: "Mounted volumes are excluded from a startup-disk scan to avoid counting duplicate or external volumes. Scan a mounted volume directly to inspect it.")
                    continue
                }

                do {
                    let info = try metadata(at: itemURL)
                    let parentID = itemURL.deletingLastPathComponent().path
                    guard nodes[parentID] != nil else {
                        if item.hasDirectoryPath { enumerator.skipDescendants() }
                        continue
                    }
                    let node = makeNode(url: itemURL, metadata: info, parentID: parentID, allocatedInodes: &allocatedInodes)
                    nodes[path] = node
                    nodes[parentID]?.children.append(path)
                    order.append(path)
                    visitedFileCount += node.fileCount
                    logicalBytes += node.logicalSize
                    if node.isSymbolicLink {
                        skippedLinkCount += 1
                        // DirectoryEnumerator never follows symlinks. Calling
                        // skipDescendants on a link can skip the next directory.
                    }
                    // Bound UI work even when a cached directory scans very
                    // quickly. The final callback always delivers exact totals.
                    if Date().timeIntervalSince(lastProgress) >= 0.1 {
                        progress(ScanProgress(fileCount: visitedFileCount, itemCount: nodes.count, logicalBytes: logicalBytes, currentPath: path))
                        lastProgress = Date()
                    }
                } catch {
                    if item.hasDirectoryPath { enumerator.skipDescendants() }
                    recordIssue(path: path, message: error.localizedDescription)
                }
            }
        }
        try Task.checkCancellation()

        // Each node adds to its parent once, giving linear aggregation without
        // repeatedly walking ancestor chains for deep directory trees.
        for id in order.reversed() {
            try Task.checkCancellation()
            guard let node = nodes[id], let parentID = node.parentID else { continue }
            nodes[parentID]?.logicalSize += node.logicalSize
            nodes[parentID]?.allocatedSize += node.allocatedSize
            nodes[parentID]?.fileCount += node.fileCount
        }
        progress(ScanProgress(fileCount: visitedFileCount, itemCount: nodes.count, logicalBytes: logicalBytes, currentPath: rootID))
        return DiskSnapshot(rootID: rootID, nodes: nodes, startedAt: startedAt, finishedAt: Date(), issues: issues, visitedFileCount: visitedFileCount, skippedLinkCount: skippedLinkCount, isPartial: isPartial)
    }

    private func metadata(at url: URL) throws -> stat {
        var value = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.lstat(path, &value)
        }
        guard result == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        return value
    }

    private func makeNode(url: URL, metadata: stat, parentID: String?, allocatedInodes: inout Set<Inode>) -> DiskNode {
        let kind = metadata.st_mode & mode_t(S_IFMT)
        let isDirectory = kind == mode_t(S_IFDIR)
        let isSymbolicLink = kind == mode_t(S_IFLNK)
        let isRegularFile = kind == mode_t(S_IFREG)
        let logicalSize = isRegularFile ? max(0, Int64(metadata.st_size)) : 0
        var allocatedSize: Int64 = 0
        if isRegularFile {
            let inode = Inode(device: metadata.st_dev, number: metadata.st_ino)
            // Only multiply-linked files need a retained identity. Most files
            // have one link, so this keeps memory overhead small on large scans.
            if metadata.st_nlink <= 1 || allocatedInodes.insert(inode).inserted {
                allocatedSize = max(0, Int64(metadata.st_blocks)) * 512
            }
        }
        return DiskNode(id: url.path, url: url, name: url.lastPathComponent, isDirectory: isDirectory, isSymbolicLink: isSymbolicLink, logicalSize: logicalSize, allocatedSize: allocatedSize, fileCount: isRegularFile ? 1 : 0, parentID: parentID, modificationDate: Date(timeIntervalSince1970: TimeInterval(metadata.st_mtimespec.tv_sec) + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000), category: FileCategory.classify(url: url, isDirectory: isDirectory))
    }
}

public enum ScanError: LocalizedError {
    case notAFileURL
    case cannotEnumerate(String)

    public var errorDescription: String? {
        switch self {
        case .notAFileURL: return "Choose a folder or volume on this Mac."
        case .cannotEnumerate(let path): return "Aster couldn’t read \(path). Choose another folder or check its access permissions."
        }
    }
}
