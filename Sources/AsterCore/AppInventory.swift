import Foundation
import Darwin

public enum AppRelatedKind: String, CaseIterable, Sendable {
    case caches, preferences, applicationSupport, containers, logs, savedState, webKit, httpStorage

    public var title: String {
        switch self {
        case .caches: return "Caches"
        case .preferences: return "Preferences"
        case .applicationSupport: return "Application Support"
        case .containers: return "App container"
        case .logs: return "Logs"
        case .savedState: return "Saved application state"
        case .webKit: return "WebKit data"
        case .httpStorage: return "HTTP storage"
        }
    }

    fileprivate var directoryName: String {
        switch self {
        case .caches: return "Caches"
        case .preferences: return "Preferences"
        case .applicationSupport: return "Application Support"
        case .containers: return "Containers"
        case .logs: return "Logs"
        case .savedState: return "Saved Application State"
        case .webKit: return "WebKit"
        case .httpStorage: return "HTTPStorages"
        }
    }

    fileprivate var suffix: String {
        switch self {
        case .preferences: return ".plist"
        case .savedState: return ".savedState"
        default: return ""
        }
    }

    public var caution: String {
        switch self {
        case .caches: return "Review before removing. Cached content may need to be downloaded or rebuilt."
        case .preferences: return "Contains settings and may include license or account preferences. Removing it can reset the app."
        case .applicationSupport: return "May contain databases, projects, profiles, or other personal app data. Inspect and back up anything you need."
        case .containers: return "May contain the app's documents, databases, and settings. This is persistent user data, not just a cache."
        case .logs: return "May contain diagnostic history needed for troubleshooting. Review before removing."
        case .savedState: return "May contain open-window and document recovery state. Close the app and save your work first."
        case .webKit: return "May contain website storage, cookies, sessions, or offline content used by the app."
        case .httpStorage: return "May contain cookies, sessions, and network data used by the app."
        }
    }
}

/// A path suggestion, never a deletion authorization. All selections start off in the UI.
public struct AppRelatedFile: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let kind: AppRelatedKind
    public let title: String
    public let reason: String
    public let caution: String
    public let ownerBundleIdentifier: String

    public init(url: URL, kind: AppRelatedKind, title: String? = nil, reason: String, caution: String? = nil, ownerBundleIdentifier: String) {
        self.url = url
        self.kind = kind
        self.title = title ?? kind.title
        self.reason = reason
        self.caution = caution ?? kind.caution
        self.ownerBundleIdentifier = ownerBundleIdentifier
    }
}

public struct InstalledApp: Identifiable, Sendable, Equatable {
    public var id: String { bundleURL.path }
    public let name: String
    public let bundleIdentifier: String
    public let bundleURL: URL
    public let relatedFiles: [AppRelatedFile]

    public init(name: String, bundleIdentifier: String, bundleURL: URL, relatedFiles: [AppRelatedFile] = []) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.relatedFiles = relatedFiles
    }
}

public struct LeftoverGroup: Identifiable, Sendable, Equatable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let title: String
    public let files: [AppRelatedFile]
    public let caution: String

    public init(bundleIdentifier: String, title: String = "Possible leftover", files: [AppRelatedFile], caution: String = "Ownership is unverified. The app may have moved, may be installed outside the scanned folders, or may be a helper for another app. Review each path; nothing is selected automatically.") {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.files = files
        self.caution = caution
    }
}

public struct AppInventoryResult: Sendable {
    public let apps: [InstalledApp]
    public let leftovers: [LeftoverGroup]
    public let warnings: [String]
    /// Complete only within the requested roots and supported Library locations.
    /// This does not imply that all installed apps anywhere on the Mac were found.
    public let isComplete: Bool
    public let isDemo: Bool

    public init(apps: [InstalledApp], leftovers: [LeftoverGroup], warnings: [String] = [], isComplete: Bool = true, isDemo: Bool = false) {
        self.apps = apps
        self.leftovers = leftovers
        self.warnings = warnings
        self.isComplete = isComplete
        self.isDemo = isDemo
    }
}

/// Read-only, deliberately narrow discovery. It never executes an app or reads
/// arbitrary user files: app Info.plists are the only file contents inspected.
public enum AppInventoryScanner {
    public static var defaultUserLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
    }

    public static var defaultRoots: [URL] {
        let personal = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        // ~/Applications is optional. Keep inaccessible roots so scan reports
        // the error; omit only a genuinely absent optional default location.
        do {
            _ = try metadata(personal)
            roots.append(personal)
        } catch {
            if !isMissing(error) { roots.append(personal) }
        }
        return roots
    }

    public static func scan(applicationRoots: [URL] = defaultRoots, userLibrary: URL = defaultUserLibrary) async throws -> AppInventoryResult {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try scanSynchronously(applicationRoots: applicationRoots, userLibrary: userLibrary)
        }
        return try await withTaskCancellationHandler {
            let result = try await worker.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            worker.cancel()
        }
    }

    private static func scanSynchronously(applicationRoots: [URL], userLibrary: URL) throws -> AppInventoryResult {
        let manager = FileManager()
        var warnings: [String] = []
        var isComplete = true
        var apps: [InstalledApp] = []
        var seenPaths = Set<String>()
        var itemsVisited = 0

        func warn(_ message: String) {
            isComplete = false
            if warnings.count < 100 { warnings.append(message) }
        }

        func inspectApp(_ url: URL) {
            do {
                let contents = url.appendingPathComponent("Contents", isDirectory: true)
                let plistURL = contents.appendingPathComponent("Info.plist")
                guard try fileType(metadata(contents)) == S_IFDIR,
                      try fileType(metadata(plistURL)) == S_IFREG else {
                    warn("Could not verify the app identity at \(url.path): metadata is missing or uses a symbolic link.")
                    return
                }
                guard try metadata(plistURL).st_size <= 1_048_576 else {
                    warn("Could not verify the app identity at \(url.path): Info.plist is unexpectedly large.")
                    return
                }
                let data = try Data(contentsOf: plistURL)
                guard let info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                      let identifier = info["CFBundleIdentifier"] as? String,
                      validIdentifier(identifier) else {
                    warn("Could not verify the app identity at \(url.path): the bundle identifier is missing or invalid.")
                    return
                }
                guard !protectedIdentifier(identifier) else { return }
                let name = [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(name: name, bundleIdentifier: identifier, bundleURL: url))
            } catch {
                warn("Could not read the app identity at \(url.path): \(error.localizedDescription)")
            }
        }

        var directories: [URL] = []
        if applicationRoots.isEmpty { warn("No application folders were selected. Possible leftovers are hidden until application discovery succeeds.") }
        for root in applicationRoots {
            try Task.checkCancellation()
            guard root.isFileURL else { warn("An application location is not a local folder: \(root.absoluteString)"); continue }
            let root = root.absoluteURL
            do {
                if let link = try symbolicLinkAncestor(root) {
                    warn("Symbolic-link application location was excluded: \(link.path)")
                } else {
                    directories.append(root)
                }
            } catch {
                warn("Could not verify application folder \(root.path): \(error.localizedDescription)")
            }
        }
        while let directory = directories.popLast() {
            try Task.checkCancellation()
            guard directory.isFileURL else { warn("An application location is not a local folder: \(directory.absoluteString)"); continue }
            guard seenPaths.insert(directory.path).inserted else { continue }
            if protectedPath(directory) {
                warn("Protected system location was excluded: \(directory.path)")
                continue
            }
            do {
                let type = try fileType(metadata(directory))
                if type == S_IFLNK {
                    warn("Symbolic-link application location was excluded: \(directory.path)")
                    continue
                }
                guard type == S_IFDIR else { warn("Application location is not a directory: \(directory.path)"); continue }
                if directory.pathExtension.lowercased() == "app" {
                    inspectApp(directory)
                    // App descendants include helper apps and private frameworks.
                    // Never enumerate inside an application package.
                    continue
                }
                let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                for child in children {
                    try Task.checkCancellation()
                    itemsVisited += 1
                    guard itemsVisited <= 50_000 else { break }
                    do {
                        let childType = try fileType(metadata(child))
                        if childType == S_IFLNK {
                            if symbolicLinkMayHideApplication(child) {
                                warn("Symbolic link was excluded from application discovery: \(child.path)")
                            }
                        } else if childType == S_IFDIR {
                            directories.append(child)
                        }
                    } catch {
                        warn("Could not inspect \(child.path): \(error.localizedDescription)")
                    }
                }
                if itemsVisited > 50_000 {
                    warn("Application discovery reached its 50,000-item limit. Select a smaller application folder; possible leftovers are hidden.")
                    break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warn("Could not read application folder \(directory.path): \(error.localizedDescription)")
            }
        }

        var candidates: [String: [AppRelatedFile]] = [:]
        let library = userLibrary.absoluteURL
        var canReadLibrary = library.isFileURL
        if canReadLibrary {
            do {
                if let link = try symbolicLinkAncestor(library) {
                    canReadLibrary = false
                    warn("Symbolic-link user Library location was excluded: \(link.path)")
                } else {
                    canReadLibrary = try fileType(metadata(library)) == S_IFDIR
                    if !canReadLibrary { warn("The user Library is not a regular directory: \(library.path)") }
                }
            } catch {
                canReadLibrary = false
                warn("Could not inspect the user Library at \(library.path): \(error.localizedDescription)")
            }
        } else {
            warn("The user Library must be a local folder.")
        }

        if canReadLibrary {
            var libraryItemsVisited = 0
            libraryLocations: for kind in AppRelatedKind.allCases {
                try Task.checkCancellation()
                let location = library.appendingPathComponent(kind.directoryName, isDirectory: true)
                do {
                    let type = try fileType(metadata(location))
                    guard type == S_IFDIR else {
                        warn("Related-data location is not a regular directory and was excluded: \(location.path)")
                        continue
                    }
                    guard let enumerator = manager.enumerator(at: location, includingPropertiesForKeys: nil,
                        options: [.skipsSubdirectoryDescendants], errorHandler: { url, error in
                            warn("Could not read related-data folder \(url.path): \(error.localizedDescription)")
                            return false
                        }) else {
                        warn("Could not enumerate related-data folder \(location.path)")
                        continue
                    }
                    while let entry = enumerator.nextObject() as? URL {
                        try Task.checkCancellation()
                        libraryItemsVisited += 1
                        if libraryItemsVisited > 50_000 {
                            warn("Related-data discovery reached its 50,000-item limit. Possible leftovers are hidden.")
                            break libraryLocations
                        }
                        let name = entry.lastPathComponent
                        guard !name.hasPrefix("."), name.hasSuffix(kind.suffix) else { continue }
                        let identifier = kind.suffix.isEmpty ? name : String(name.dropLast(kind.suffix.count))
                        guard validIdentifier(identifier), !protectedIdentifier(identifier) else { continue }
                        do {
                            let entryType = try fileType(metadata(entry))
                            if entryType == S_IFLNK {
                                warn("Symbolic-link related data was excluded: \(entry.path)")
                                continue
                            }
                            guard entryType == (kind == .preferences ? S_IFREG : S_IFDIR) else { continue }
                            let candidate = AppRelatedFile(url: entry, kind: kind,
                                reason: "Exact bundle-identifier path match for \(identifier). Confirm the contents before removing anything.",
                                ownerBundleIdentifier: identifier)
                            candidates[identifier, default: []].append(candidate)
                        } catch {
                            warn("Could not inspect related data at \(entry.path): \(error.localizedDescription)")
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Supported Library directories are optional. A directory
                    // not present is different from one we lack permission to read.
                    if !isMissing(error) { warn("Could not read related-data folder \(location.path): \(error.localizedDescription)") }
                }
            }
        }

        apps = apps.map { app in
            InstalledApp(name: app.name, bundleIdentifier: app.bundleIdentifier,
                         bundleURL: app.bundleURL, relatedFiles: candidates[app.bundleIdentifier] ?? [])
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        let installedIDs = Set(apps.map { $0.bundleIdentifier.lowercased() })
        var leftovers: [LeftoverGroup] = []
        if isComplete {
            for (identifier, files) in candidates {
                try Task.checkCancellation()
                guard identifier.split(separator: ".").count >= 3,
                      !installedIDs.contains(identifier.lowercased()),
                      !installedIDs.contains(where: { identifier.lowercased().hasPrefix($0 + ".") }) else { continue }
                let unverified = files.map {
                    AppRelatedFile(url: $0.url, kind: $0.kind,
                                   reason: "No matching app identity was found in the selected application folders. This does not prove that the file is unused.",
                                   ownerBundleIdentifier: identifier)
                }
                leftovers.append(LeftoverGroup(bundleIdentifier: identifier, files: unverified))
            }
            leftovers.sort { $0.bundleIdentifier.localizedStandardCompare($1.bundleIdentifier) == .orderedAscending }
        } else {
            warnings.append("Discovery was incomplete. Possible leftovers are hidden because an unreadable or unidentified app could still own these files.")
        }
        try Task.checkCancellation()
        return AppInventoryResult(apps: apps, leftovers: leftovers, warnings: warnings, isComplete: isComplete)
    }

    private static func metadata(_ url: URL) throws -> stat {
        var result = stat()
        let status = url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return Int32(-1) }
            return Darwin.lstat(pointer, &result)
        }
        guard status == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: url.path])
        }
        return result
    }

    private static func fileType(_ value: stat) -> mode_t { value.st_mode & mode_t(S_IFMT) }

    /// Inspect a link's destination metadata only, never enumerate through it.
    /// Protected system aliases and ordinary document links cannot conceal a
    /// removable app, so they do not make discovery incomplete. Unknown,
    /// broken, app-package, or other directory links remain conservative gaps.
    private static func symbolicLinkMayHideApplication(_ url: URL) -> Bool {
        guard let resolvedPath = url.withUnsafeFileSystemRepresentation({ path -> String? in
            guard let path, let resolved = Darwin.realpath(path, nil) else { return nil }
            defer { free(resolved) }
            return String(cString: resolved)
        }) else { return true }
        let destination = URL(fileURLWithPath: resolvedPath)
        if protectedPath(destination) { return false }
        guard url.pathExtension.lowercased() != "app",
              let info = try? metadata(destination), fileType(info) == S_IFREG else { return true }
        return false
    }

    /// Root components are checked individually: lstat of the final path alone
    /// would still traverse a symlink earlier in that path.
    private static func symbolicLinkAncestor(_ url: URL) throws -> URL? {
        var componentURL = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents where component != "/" {
            try Task.checkCancellation()
            componentURL.appendPathComponent(component)
            if try fileType(metadata(componentURL)) == S_IFLNK { return componentURL }
        }
        return nil
    }

    private static func isMissing(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    }

    private static func validIdentifier(_ value: String) -> Bool {
        guard value.count <= 255, !value.isEmpty else { return false }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let initial = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let valid = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return parts.allSatisfy { part in
            guard let first = part.unicodeScalars.first, initial.contains(first) else { return false }
            return part.unicodeScalars.allSatisfy(valid.contains)
        }
    }

    private static func protectedIdentifier(_ value: String) -> Bool {
        let identifier = value.lowercased()
        return identifier == "com.apple" || identifier.hasPrefix("com.apple.") || identifier.hasPrefix("group.")
    }

    private static func protectedPath(_ url: URL) -> Bool {
        let path = url.path
        return ["/System", "/usr", "/bin", "/sbin", "/Library/Apple"].contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
