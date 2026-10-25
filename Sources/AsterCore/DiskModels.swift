import Foundation

public enum FileCategory: String, CaseIterable, Sendable {
    case applications, developer, documents, media, archives, other

    public var displayName: String {
        switch self {
        case .applications: return "Applications"
        case .developer: return "Developer"
        case .documents: return "Documents"
        case .media: return "Media"
        case .archives: return "Archives"
        case .other: return "Other"
        }
    }

    public static func classify(url: URL, isDirectory: Bool) -> FileCategory {
        let components = url.pathComponents.map { $0.lowercased() }
        if components.contains(where: { $0.hasSuffix(".app") }) { return .applications }
        let developerFolders: Set<String> = ["developer", "xcode", "deriveddata", "node_modules", ".git", ".build", ".swiftpm", ".npm", ".cargo", ".rustup", ".gradle", "venv", ".venv", "pods", "coresimulator"]
        if components.contains(where: developerFolders.contains) { return .developer }
        let ext = url.pathExtension.lowercased()
        if ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "iso", "pkg"].contains(ext) { return .archives }
        if ["jpg", "jpeg", "png", "heic", "gif", "webp", "svg", "psd", "raw", "tiff", "tif", "mp4", "mov", "mkv", "avi", "mp3", "m4a", "wav", "aiff", "flac", "photoslibrary", "fcpbundle"].contains(ext) { return .media }
        if ["swift", "m", "mm", "h", "c", "cpp", "js", "jsx", "ts", "tsx", "py", "rs", "go", "java", "ipynb", "xcodeproj", "xcworkspace"].contains(ext) { return .developer }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf", "csv", "epub"].contains(ext) { return .documents }
        if components.contains(where: { ["pictures", "movies", "music"].contains($0) }) { return .media }
        if components.contains("documents") { return .documents }
        if isDirectory && components.last == "applications" { return .applications }
        return .other
    }
}

/// A filesystem entry. Directory sizes are the sum of their scanned descendants.
/// Logical sizes count every hard-link name; allocated sizes count each inode once.
/// Symlinks are shown but neither followed nor included in byte/file totals.
public struct DiskNode: Identifiable, Sendable, Equatable {
    public var id: String
    public var url: URL
    public var name: String
    public var isDirectory: Bool
    public var isSymbolicLink: Bool
    public var logicalSize: Int64
    public var allocatedSize: Int64
    public var fileCount: Int
    public var children: [String]
    public var parentID: String?
    public var modificationDate: Date?
    public var category: FileCategory

    public init(id: String, url: URL, name: String, isDirectory: Bool, isSymbolicLink: Bool = false, logicalSize: Int64, allocatedSize: Int64, fileCount: Int, children: [String] = [], parentID: String? = nil, modificationDate: Date? = nil, category: FileCategory) {
        self.id = id
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.fileCount = fileCount
        self.children = children
        self.parentID = parentID
        self.modificationDate = modificationDate
        self.category = category
    }
}

public struct ScanProgress: Sendable {
    public var fileCount: Int
    public var itemCount: Int
    public var logicalBytes: Int64
    public var currentPath: String

    public init(fileCount: Int, itemCount: Int, logicalBytes: Int64, currentPath: String) {
        self.fileCount = fileCount
        self.itemCount = itemCount
        self.logicalBytes = logicalBytes
        self.currentPath = currentPath
    }
}

public struct ScanIssue: Identifiable, Sendable {
    public var id: String
    public var path: String
    public var message: String

    public init(id: String = UUID().uuidString, path: String, message: String) {
        self.id = id
        self.path = path
        self.message = message
    }
}

public struct DiskSnapshot: Sendable {
    public var rootID: String
    public var nodes: [String: DiskNode]
    public var startedAt: Date
    public var finishedAt: Date
    public var issues: [ScanIssue]
    public var visitedFileCount: Int
    public var skippedLinkCount: Int
    public var isDemo: Bool
    public var isPartial: Bool

    public var root: DiskNode { nodes[rootID]! }
    public var duration: TimeInterval { finishedAt.timeIntervalSince(startedAt) }

    public init(rootID: String, nodes: [String: DiskNode], startedAt: Date, finishedAt: Date, issues: [ScanIssue] = [], visitedFileCount: Int, skippedLinkCount: Int = 0, isDemo: Bool = false, isPartial: Bool = false) {
        precondition(nodes[rootID] != nil, "A snapshot must contain its root node")
        self.rootID = rootID
        self.nodes = nodes
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.issues = issues
        self.visitedFileCount = visitedFileCount
        self.skippedLinkCount = skippedLinkCount
        self.isDemo = isDemo
        self.isPartial = isPartial
    }

    /// The same query can drive a large-file list and category-filtered search.
    /// Search never touches disk and matches names and full paths case-insensitively.
    public func files(matching query: String = "", minimumSize: Int64 = 0, category: FileCategory? = nil, within directoryID: String? = nil) -> [DiskNode] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = directoryID.map { $0 == "/" ? "/" : $0 + "/" }
        return nodes.values.filter { node in
            !node.isDirectory && !node.isSymbolicLink
                && node.logicalSize >= minimumSize
                && (category == nil || node.category == category)
                && (prefix == nil || node.id.hasPrefix(prefix!))
                && (search.isEmpty || node.name.localizedCaseInsensitiveContains(search) || node.url.path.localizedCaseInsensitiveContains(search))
        }.sorted { lhs, rhs in
            lhs.logicalSize == rhs.logicalSize ? lhs.id < rhs.id : lhs.logicalSize > rhs.logicalSize
        }
    }

    /// Categories describe files, so nested directories never double-count totals.
    public var categoryTotals: [FileCategory: Int64] {
        nodes.values.reduce(into: Dictionary(uniqueKeysWithValues: FileCategory.allCases.map { ($0, Int64(0)) })) { result, node in
            if !node.isDirectory && !node.isSymbolicLink { result[node.category, default: 0] += node.logicalSize }
        }
    }
}
