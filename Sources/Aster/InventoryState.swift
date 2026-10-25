import AppKit
import Observation
import AsterCore

@MainActor @Observable
final class InventoryState {
    var result = AppInventoryResult(apps: [], leftovers: [], isComplete: false)
    private(set) var hasLoaded = false
    var isLoading = false
    var errorMessage: String?
    var statusMessage: String?
    var query = ""
    var selectedAppID: String? {
        didSet {
            guard oldValue != selectedAppID else { return }
            selectedRelatedIDs = []
            includeSelectedApp = true
        }
    }
    var includeSelectedApp = true
    var selectedRelatedIDs: Set<String> = []
    var selectedLeftoverIDs: Set<String> = []
    private(set) var runningBundleIdentifiers: Set<String> = []
    private(set) var runningBundlePaths: Set<String> = []

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var hasStartedInitialLoad = false
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var applicationRoots = AppInventoryScanner.defaultRoots
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let workspaceNotifications = NSWorkspace.shared.notificationCenter

    init() {
        selectedAppID = result.apps.first?.id
        refreshRunningApplications()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = workspaceNotifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshRunningApplications() }
            }
            workspaceObservers.append(observer)
        }
    }

    deinit {
        loadTask?.cancel()
        for observer in workspaceObservers { workspaceNotifications.removeObserver(observer) }
    }

    var locationsDescription: String {
        applicationRoots.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")
    }
    var selectedApp: InstalledApp? { result.apps.first { $0.id == selectedAppID } }
    var filteredApps: [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return result.apps }
        return result.apps.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || (identifier(for: $0)?.localizedCaseInsensitiveContains(needle) ?? false)
                || $0.bundleURL.path.localizedCaseInsensitiveContains(needle)
        }
    }

    func identifier(for app: InstalledApp) -> String? {
        let value: String? = app.bundleIdentifier
        return value.flatMap { $0.isEmpty ? nil : $0 }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        return runningBundlePaths.contains(app.bundleURL.standardizedFileURL.path)
            || isRunning(ownerBundleIdentifier: identifier(for: app))
    }

    func isRunning(ownerBundleIdentifier: String?) -> Bool {
        guard let owner = ownerBundleIdentifier else { return false }
        return runningBundleIdentifiers.contains { $0 == owner || $0.hasPrefix(owner + ".") }
    }

    func hasOtherCopy(_ app: InstalledApp) -> Bool {
        guard let identifier = identifier(for: app) else { return false }
        return result.apps.contains { $0.id != app.id && self.identifier(for: $0) == identifier }
    }

    func refreshRunningApplications() {
        let applications = NSWorkspace.shared.runningApplications
        runningBundleIdentifiers = Set(applications.compactMap(\.bundleIdentifier))
        runningBundlePaths = Set(applications.compactMap { $0.bundleURL?.standardizedFileURL.path })
    }

    func loadIfNeeded() {
        guard !hasStartedInitialLoad else { return }
        load()
    }

    func load() {
        hasStartedInitialLoad = true
        loadTask?.cancel()
        let currentRevision = UUID()
        revision = currentRevision
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        refreshRunningApplications()
        let roots = applicationRoots
        loadTask = Task { [weak self] in
            do {
                let inventory = try await AppInventoryScanner.scan(applicationRoots: roots)
                guard let self, self.revision == currentRevision else { return }
                guard !Task.isCancelled else {
                    self.isLoading = false
                    return
                }
                let previousID = self.selectedAppID
                self.result = inventory
                self.hasLoaded = true
                self.selectedRelatedIDs = []
                self.selectedLeftoverIDs = []
                self.includeSelectedApp = true
                let visibleApps = self.filteredApps
                self.selectedAppID = visibleApps.contains(where: { $0.id == previousID }) ? previousID : visibleApps.first?.id
                self.isLoading = false
                self.statusMessage = inventory.isComplete
                    ? "Checked \(inventory.apps.count.formatted()) applications. Nothing has been added to your cleanup queue."
                    : "Some locations couldn’t be checked. See the scan notes before reviewing these results."
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

    func chooseApplicationsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose an applications folder"
        panel.message = "Check this folder for applications alongside the standard app locations."
        panel.prompt = "Scan folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                if !self.applicationRoots.contains(where: { $0.standardizedFileURL == folder.standardizedFileURL }) {
                    self.applicationRoots.append(folder)
                }
                self.load()
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        revision = UUID()
        isLoading = false
        statusMessage = hasLoaded
            ? "Scan cancelled. Previous results are still available."
            : "Scan cancelled. Scan applications when you’re ready."
    }

    func refreshAfterCleanup() {
        guard hasLoaded else { return }
        load()
    }

    func toggleRelated(_ id: String) {
        if selectedRelatedIDs.contains(id) { selectedRelatedIDs.remove(id) }
        else { selectedRelatedIDs.insert(id) }
    }

    func toggleLeftover(_ id: String) {
        if selectedLeftoverIDs.contains(id) { selectedLeftoverIDs.remove(id) }
        else { selectedLeftoverIDs.insert(id) }
    }
}
