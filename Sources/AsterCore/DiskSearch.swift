import Foundation

public enum FileSort: String, CaseIterable, Sendable {
    case size = "Largest first"
    case name = "Name"
    case modified = "Recently modified"
}

public struct FileSearchResult: Sendable {
    public let files: [DiskNode]
    public let totalCount: Int
    public let totalBytes: Int64
}

public enum DiskSearch {
    /// Searches file metadata only. Directories and links are intentionally excluded.
    public static func find(in snapshot: DiskSnapshot, query: String = "", category: FileCategory? = nil,
                            minimumSize: Int64 = 0, sort: FileSort = .size, limit: Int = 500) -> FileSearchResult {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [DiskNode] = []
        var bytes: Int64 = 0
        for node in snapshot.nodes.values {
            if Task.isCancelled { return FileSearchResult(files: [], totalCount: 0, totalBytes: 0) }
            guard !node.isDirectory, !node.isSymbolicLink, node.logicalSize >= minimumSize else { continue }
            if let category, node.category != category { continue }
            if !needle.isEmpty && node.url.path.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) == nil { continue }
            matches.append(node)
            bytes = bytes.addingReportingOverflow(node.logicalSize).overflow ? Int64.max : bytes + node.logicalSize
        }
        if Task.isCancelled { return FileSearchResult(files: [], totalCount: 0, totalBytes: 0) }
        matches.sort { a, b in
            switch sort {
            case .size:
                if a.logicalSize != b.logicalSize { return a.logicalSize > b.logicalSize }
            case .name:
                let comparison = a.name.localizedStandardCompare(b.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .modified:
                let left = a.modificationDate ?? .distantPast
                let right = b.modificationDate ?? .distantPast
                if left != right { return left > right }
            }
            return a.id < b.id
        }
        return FileSearchResult(files: Array(matches.prefix(max(0, limit))), totalCount: matches.count, totalBytes: bytes)
    }
}
