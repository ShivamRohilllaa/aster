import AppKit
import SwiftUI
import Observation
import AsterCore

enum AppSection: String, CaseIterable {
    case overview = "Overview"
    case largeFiles = "Large files"
    case cleanup = "Cleanup"
    case caches = "Caches & logs"
    case applications = "Applications"
    case leftovers = "Leftovers"
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .cleanup: return "tray"
        case .caches: return "externaldrive.badge.timemachine"
        case .applications: return "square.stack.3d.up"
        case .leftovers: return "sparkles"
        }
    }
    var showsInspector: Bool { self == .overview || self == .largeFiles }
}

enum AppSheet: String, Identifiable {
    case scanDetails, about
    var id: String { rawValue }
}

@MainActor @Observable
final class AppState {
    var snapshot: DiskSnapshot
    var hasScannedFolder = false
    var section: AppSection = .overview
    var mapRootID: String
    var selectedID: String?
    var query = "" { didSet { scheduleSearch() } }
    var category: FileCategory? { didSet { scheduleSearch() } }
    var minimumSize: Int64 = 0 { didSet { scheduleSearch() } }
    var sort: FileSort = .size { didSet { scheduleSearch() } }
    var files: [DiskNode] = []
    var overviewFiles: [DiskNode] = []
    var matchingCount = 0
    var matchingBytes: Int64 = 0
    var isSearching = false
    var isScanning = false
    var progress: ScanProgress?
    var scanURL: URL?
    var errorMessage: String?
    var notice: String?
    var sheet: AppSheet?
    var categoryTotals: [FileCategory: Int64] = [:]
    let license: LicenseController
    let cleanup: CleanupState
    let inventory = InventoryState()
    let cacheDiscovery: CleanupDiscoveryState

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var searchWorker: Task<FileSearchResult, Never>?
    @ObservationIgnored private var scanRevision = UUID()
    @ObservationIgnored private var searchRevision = UUID()

    init() {
        let configuration = LicenseConfiguration.bundled()
        let license = LicenseController(configuration: configuration,
                                        store: KeychainLicenseStore(configuration: configuration))
        self.license = license
        cleanup = CleanupState(license: license)
        cacheDiscovery = CleanupDiscoveryState(license: license)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let root = DiskNode(id: home.path, url: home, name: home.lastPathComponent, isDirectory: true,
                            logicalSize: 0, allocatedSize: 0, fileCount: 0, category: .other)
        snapshot = DiskSnapshot(rootID: root.id, nodes: [root.id: root], startedAt: Date(), finishedAt: Date(), visitedFileCount: 0)
        mapRootID = root.id
        updateCategoryTotals()
        scheduleSearch()
        cleanup.didMoveFiles = { [weak self] urls in self?.refreshAfterCleanup(urls) }
    }

    var selectedNode: DiskNode? { selectedID.flatMap { snapshot.nodes[$0] } }
    var mapRoot: DiskNode { snapshot.nodes[mapRootID] ?? snapshot.root }
    var breadcrumbs: [DiskNode] {
        var path: [DiskNode] = []
        var current: DiskNode? = mapRoot
        while let node = current, path.count < 64 {
            path.append(node)
            current = node.parentID.flatMap { snapshot.nodes[$0] }
        }
        return path.reversed()
    }

    func chooseFolder() {
        guard !cleanup.isTrashing else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a folder or disk to scan"
        panel.prompt = "Scan folder"
        panel.message = "Scanning reads file names and sizes. Cleanup is a separate action that always requires your review."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.startScan(url) }
        }
    }

    func startScan(_ url: URL, preservingSection: Bool = false) {
        guard !cleanup.isTrashing else { return }
        scanTask?.cancel()
        let revision = UUID()
        scanRevision = revision
        isScanning = true
        scanURL = url
        progress = nil
        errorMessage = nil
        notice = nil
        scanTask = Task { [weak self] in
            do {
                let owner = self
                let result = try await DiskScanner().scan(url: url) { update in
                    Task { @MainActor in
                        guard owner?.scanRevision == revision else { return }
                        owner?.progress = update
                    }
                }
                guard let self, self.scanRevision == revision, !Task.isCancelled else { return }
                self.snapshot = result
                self.hasScannedFolder = true
                self.clearDerivedResults()
                self.mapRootID = result.rootID
                self.selectedID = result.root.children.first
                self.isScanning = false
                self.query = ""
                self.category = nil
                self.minimumSize = 0
                if !preservingSection { self.section = .overview }
                self.updateCategoryTotals()
                self.scheduleSearch()
            } catch is CancellationError {
                guard let self, self.scanRevision == revision else { return }
                self.isScanning = false
                self.notice = "Scan cancelled. Your previous results are still here."
            } catch {
                guard let self, self.scanRevision == revision else { return }
                self.isScanning = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelScan() {
        scanRevision = UUID()
        scanTask?.cancel()
        isScanning = false
        progress = nil
        notice = "Scan cancelled. Your previous results are still here."
    }
    func rescan() {
        switch section {
        case .applications, .leftovers: inventory.load()
        case .caches: cacheDiscovery.load()
        case .cleanup: break
        default: startScan(snapshot.root.url, preservingSection: true)
        }
    }
    func navigate(to id: String) {
        guard let node = snapshot.nodes[id] else { return }
        selectedID = id
        guard node.isDirectory else { return }
        mapRootID = id
        section = .overview
    }
    func showFiles(category: FileCategory? = nil) {
        self.category = category
        section = .largeFiles
    }
    func resetFilters() {
        query = ""
        category = nil
        minimumSize = 0
        sort = .size
    }
    func reveal(_ node: DiskNode) {
        guard license.isPro, hasScannedFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
    func copyPath(_ node: DiskNode) {
        guard license.isPro else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }
    func queueForCleanup(_ node: DiskNode) {
        let owner = applicationIdentifierForCleanup(node)
        cleanup.add(CleanupCandidate(url: node.url, title: node.name,
                                     reason: "Selected from your storage scan", kind: owner != nil ? "Application" : node.isDirectory ? "Folder" : "File",
                                     symbol: owner != nil ? "app.fill" : node.isDirectory ? "folder" : node.category.symbol,
                                     logicalSize: node.logicalSize, ownerBundleID: owner))
    }
    private func applicationIdentifierForCleanup(_ node: DiskNode) -> String? {
        guard node.isDirectory, !node.isSymbolicLink, node.url.pathExtension.lowercased() == "app" else { return nil }
        let path = node.url.path.lowercased()
        let libraryRoots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library").path, "/Library", "/System/Library"]
        guard !libraryRoots.contains(where: { path == $0.lowercased() || path.hasPrefix($0.lowercased() + "/") }) else { return nil }
        let info = node.url.appendingPathComponent("Contents/Info.plist")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: info.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value < 2_000_000,
              let identifier = Bundle(url: node.url)?.bundleIdentifier, !identifier.isEmpty else { return nil }
        return identifier
    }
    private func refreshAfterCleanup(_ urls: [URL]) {
        inventory.refreshAfterCleanup()
        cacheDiscovery.refreshAfterCleanup()
        guard hasScannedFolder else { return }
        let root = snapshot.root.url
        let affectsScan = urls.contains { url in
            url.path == root.path || url.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
                || root.path.hasPrefix(url.path + "/")
        }
        guard affectsScan else { return }
        if FileManager.default.fileExists(atPath: root.path) {
            startScan(root, preservingSection: true)
        } else {
            scanTask?.cancel()
            scanRevision = UUID()
            isScanning = false
            var emptyRoot = snapshot.root
            emptyRoot.logicalSize = 0
            emptyRoot.allocatedSize = 0
            emptyRoot.children = []
            emptyRoot.fileCount = 0
            snapshot = DiskSnapshot(rootID: emptyRoot.id, nodes: [emptyRoot.id: emptyRoot],
                                    startedAt: Date(), finishedAt: Date(),
                                    issues: [ScanIssue(path: root.path, message: "This scanned folder was moved to Trash. Choose another folder to continue.")],
                                    visitedFileCount: 0, isPartial: true)
            mapRootID = emptyRoot.id
            selectedID = nil
            clearDerivedResults()
            scheduleSearch()
            notice = "The scanned folder was moved to Trash. Choose another folder to continue."
        }
    }
    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    private func clearDerivedResults() {
        files = []
        overviewFiles = []
        categoryTotals = [:]
        matchingCount = 0
        matchingBytes = 0
    }
    private func updateCategoryTotals() {
        let snapshot = self.snapshot
        let nodes = snapshot.nodes
        let revision = snapshot.finishedAt
        Task.detached(priority: .utility) {
            var totals: [FileCategory: Int64] = [:]
            for node in nodes.values where !node.isDirectory && !node.isSymbolicLink {
                totals[node.category, default: 0] += node.logicalSize
            }
            let finishedTotals = totals
            let largest = DiskSearch.find(in: snapshot, limit: 3).files
            await MainActor.run { [weak self] in
                guard self?.snapshot.finishedAt == revision else { return }
                self?.categoryTotals = finishedTotals
                self?.overviewFiles = largest
            }
        }
    }
    private func scheduleSearch() {
        searchTask?.cancel()
        searchWorker?.cancel()
        let revision = UUID()
        searchRevision = revision
        isSearching = true
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            let snapshot = self.snapshot, query = self.query, category = self.category
            let minimum = self.minimumSize, sort = self.sort
            let worker = Task.detached(priority: .userInitiated) {
                DiskSearch.find(in: snapshot, query: query, category: category, minimumSize: minimum, sort: sort)
            }
            self.searchWorker = worker
            let result = await worker.value
            guard !Task.isCancelled, self.searchRevision == revision else { return }
            self.files = result.files
            self.matchingCount = result.totalCount
            self.matchingBytes = result.totalBytes
            self.isSearching = false
        }
    }
}
