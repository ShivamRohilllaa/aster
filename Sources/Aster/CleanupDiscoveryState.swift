import AppKit
import Observation
import AsterCore

@MainActor @Observable
final class CleanupDiscoveryState {
    let license: LicenseController
    var result = CleanupDiscoveryResult(entries: [], warnings: [], isComplete: false)
    private(set) var hasLoaded = false
    var isLoading = false
    var errorMessage: String?
    var statusMessage: String?
    var query = ""
    var area: CleanupArea?
    var selectedIDs: Set<String> = []
    private(set) var runningBundleIdentifiers: Set<String> = []

    @ObservationIgnored private var hasStartedInitialLoad = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let workspaceNotifications = NSWorkspace.shared.notificationCenter

    init(license: LicenseController) {
        self.license = license
        refreshRunningApplications()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspaceNotifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunningApplications() }
            })
        }
    }
    deinit {
        operation?.cancel()
        for observer in observers { workspaceNotifications.removeObserver(observer) }
    }

    var filteredEntries: [CleanupDiscoveryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.entries.filter { entry in
            (area == nil || entry.area == area)
                && (needle.isEmpty || entry.title.localizedCaseInsensitiveContains(needle)
                    || entry.url.path.localizedCaseInsensitiveContains(needle))
        }.sorted {
            $0.logicalSize == $1.logicalSize ? $0.id < $1.id : $0.logicalSize > $1.logicalSize
        }
    }
    var totalBytes: Int64 { sum(result.entries.map(\.logicalSize)) }
    var selectedEntries: [CleanupDiscoveryEntry] {
        result.entries.filter { selectedIDs.contains($0.id) && blockedReason(for: $0) == nil }
    }
    var selectedBytes: Int64 { sum(selectedEntries.map(\.logicalSize)) }

    func blockedReason(for entry: CleanupDiscoveryEntry) -> String? {
        if let reason = entry.blockedReason { return reason }
        if entry.isPartial { return "This item couldn’t be read completely. Scan again before reviewing it for cleanup." }
        if let owner = entry.ownerBundleIdentifier,
           runningBundleIdentifiers.contains(where: { $0 == owner || $0.hasPrefix(owner + ".") }) {
            return "The owning application is running. Quit it before adding this item to the queue."
        }
        return nil
    }
    func toggle(_ id: String) {
        guard !isLoading, let entry = result.entries.first(where: { $0.id == id }), blockedReason(for: entry) == nil else { return }
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }
    func refreshRunningApplications() {
        runningBundleIdentifiers = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
    func loadIfNeeded() {
        guard !hasStartedInitialLoad else { return }
        load()
    }
    func load() {
        hasStartedInitialLoad = true
        operation?.cancel()
        revision = UUID()
        let currentRevision = revision
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        refreshRunningApplications()
        operation = Task { [weak self] in
            do {
                let discovery = try await CleanupDiscoveryScanner.scan()
                guard let self, self.revision == currentRevision else { return }
                self.isLoading = false
                guard !Task.isCancelled else { return }
                self.result = discovery
                self.hasLoaded = true
                self.selectedIDs = []
                if !discovery.isComplete {
                    self.statusMessage = "Some locations couldn’t be checked completely. Affected items are unavailable for cleanup; review the scan notes."
                }
            } catch is CancellationError {
                guard let self, self.revision == currentRevision else { return }
                self.isLoading = false
            } catch {
                guard let self, self.revision == currentRevision else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    func cancel() {
        operation?.cancel()
        revision = UUID()
        isLoading = false
        statusMessage = hasLoaded ? "Scan cancelled. Previous results are still here." : "Scan cancelled. Start another scan when you’re ready."
    }
    func refreshAfterCleanup() {
        guard hasLoaded else { return }
        load()
    }
    func reveal(_ url: URL) {
        guard license.isPro else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func queueSelected(into cleanup: CleanupState) {
        guard !isLoading, !cleanup.isPreparing, !cleanup.isTrashing else { return }
        refreshRunningApplications()
        let entries = selectedEntries.filter { !cleanup.contains($0.url) }
        for entry in entries {
            cleanup.add(CleanupCandidate(url: entry.url, title: entry.title,
                                         reason: cacheReviewReason(for: entry.area) + (entry.note.isEmpty ? "" : " " + entry.note), kind: entry.area.title,
                                         symbol: cacheAreaSymbol(entry.area), logicalSize: entry.logicalSize,
                                         ownerBundleID: entry.ownerBundleIdentifier))
        }
        for entry in entries { selectedIDs.remove(entry.id) }
        statusMessage = entries.isEmpty
            ? "No new items were added. Check the selection and close any running owner applications."
            : "Added \(entries.count) \(entries.count == 1 ? "item" : "items") to the cleanup queue. Review the exact selection before moving anything to Trash."
    }
    private func sum(_ sizes: [Int64]) -> Int64 {
        sizes.reduce(0) { current, next in
            let total = current.addingReportingOverflow(max(0, next))
            return total.overflow ? Int64.max : total.partialValue
        }
    }
}

func cacheReviewReason(for area: CleanupArea) -> String {
    switch area {
    case .caches: return "App cache selected for review. The app may download or rebuild this data on its next launch."
    case .logs: return "Log files selected for review. Removing them discards diagnostic history that may be useful for troubleshooting."
    case .developer: return "Developer cache selected for review. Tools may rebuild or download data on the next run; close active builds first."
    }
}

func cacheAreaSymbol(_ area: CleanupArea) -> String {
    switch area {
    case .caches: return "square.stack.3d.up"
    case .logs: return "doc.text"
    case .developer: return "curlybraces"
    }
}
