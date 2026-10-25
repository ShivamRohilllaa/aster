import AppKit
import Observation
import AsterCore

struct CleanupCandidate: Identifiable {
    let url: URL
    let title: String
    let reason: String
    let kind: String
    let symbol: String
    let logicalSize: Int64?
    let ownerBundleID: String?
    var id: String { url.path }
}

struct CleanupPreviewRow: Identifiable {
    let id: String
    let url: URL
    let title: String
    let logicalSize: Int64
    let fileCount: Int
    let blockedReason: String?
    let warnings: [String]
    let reason: String
}

struct CleanupReview: Identifiable {
    let id: UUID
    let items: [CleanupPreviewRow]
    let notes: [String]
}

enum CleanupOutcomeStatus: String {
    case moved, failed, skipped
}

struct CleanupOutcome: Identifiable {
    let id: String
    let url: URL
    let title: String
    let status: CleanupOutcomeStatus
    let message: String
    let trashURL: URL?
}

@MainActor @Observable
final class CleanupState {
    let license: LicenseController
    var queue: [CleanupCandidate] = []
    var isPreparing = false
    var isTrashing = false
    var errorMessage: String?
    var statusMessage: String?
    var review: CleanupReview?
    var selectedPreviewIDs: Set<String> = []
    var results: [CleanupOutcome] = []
    @ObservationIgnored var didMoveFiles: (([URL]) -> Void)?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private let service: TrashService
    @ObservationIgnored private var prepared: TrashPreview?

    init(license: LicenseController, service: TrashService = TrashService()) {
        self.license = license
        self.service = service
    }

    var hasProAccess: Bool { license.isPro }

    var selectedRows: [CleanupPreviewRow] {
        review?.items.filter { selectedPreviewIDs.contains($0.id) && $0.blockedReason == nil } ?? []
    }
    var selectedCount: Int { selectedRows.count }
    var selectedBytes: Int64 { selectedRows.reduce(0) { $0 + $1.logicalSize } }
    var selectedFileCount: Int { selectedRows.reduce(0) { $0 + $1.fileCount } }
    var queueBytes: Int64 { queue.reduce(0) { $0 + ($1.logicalSize ?? 0) } }
    var canPrepare: Bool { !queue.isEmpty && !isPreparing && !isTrashing }
    var canConfirm: Bool { review != nil && selectedCount > 0 && !isTrashing && !isPreparing }

    func add(_ candidate: CleanupCandidate) {
        guard !isTrashing, !isPreparing else { return }
        if let index = queue.firstIndex(where: { $0.id == candidate.id }) {
            // A storage-scan selection may arrive before inventory identifies its
            // owner. Preserve that ownership and its data-specific explanation.
            let existing = queue[index]
            if existing.ownerBundleID == nil, candidate.ownerBundleID != nil {
                queue[index] = CleanupCandidate(url: existing.url, title: candidate.title,
                                                reason: candidate.reason, kind: candidate.kind,
                                                symbol: candidate.symbol,
                                                logicalSize: existing.logicalSize ?? candidate.logicalSize,
                                                ownerBundleID: candidate.ownerBundleID)
                invalidatePreview()
            }
            return
        }
        queue.append(candidate)
        invalidatePreview()
    }
    func contains(_ url: URL) -> Bool { queue.contains { $0.url.path == url.path } }
    func remove(id: String) {
        guard !isTrashing, !isPreparing else { return }
        queue.removeAll { $0.id == id }
        invalidatePreview()
    }
    func clear() {
        guard !isTrashing else { return }
        operation?.cancel()
        revision = UUID()
        isPreparing = false
        queue = []
        invalidatePreview()
    }
    func togglePreviewItem(id: String) {
        guard !isTrashing, review?.items.contains(where: { $0.id == id && $0.blockedReason == nil }) == true else { return }
        if selectedPreviewIDs.contains(id) { selectedPreviewIDs.remove(id) } else { selectedPreviewIDs.insert(id) }
    }
    func dismissReview() {
        guard !isTrashing else { return }
        invalidatePreview()
    }
    func cancelOperation() {
        operation?.cancel()
        if isPreparing {
            revision = UUID()
            isPreparing = false
            statusMessage = "Preview cancelled. No files were moved."
        }
        // Execution keeps its revision so already-completed moves are reported.
    }
    func reveal(_ url: URL) {
        guard license.isPro else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func revealTrash(_ item: CleanupOutcome) {
        if let url = item.trashURL { reveal(url) }
    }
    private func invalidatePreview() {
        review = nil
        selectedPreviewIDs = []
        prepared = nil
    }
    private func runningAppProtection() -> [URL] {
        var urls = NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
        urls.append(Bundle.main.bundleURL)
        // Data belonging to a running app must also remain in place.
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Protect known Library locations even when a file was queued directly
        // from the disk scan and has no inventory owner metadata.
        urls += runningIDs.flatMap { CleanupAppDataPaths.urls(for: $0) }
        urls += queue.filter { candidate in
            guard let owner = candidate.ownerBundleID ?? CleanupAppDataPaths.owner(of: candidate.url) else { return false }
            return runningIDs.contains { $0 == owner || $0.hasPrefix(owner + ".") }
        }.map(\.url)
        return urls
    }

    func prepareReview() {
        guard canPrepare else { return }
        errorMessage = nil
        statusMessage = nil
        let candidates = queue
        isPreparing = true
        let revision = UUID()
        self.revision = revision
        let protected = runningAppProtection()
        operation = Task { [weak self, service] in
            let preview = await service.prepare(urls: candidates.map(\.url), protectedURLs: protected)
            guard let self, self.revision == revision else { return }
            self.isPreparing = false
            guard !Task.isCancelled, !preview.isCancelled else {
                self.statusMessage = "Preview cancelled. No files were moved."
                return
            }
            self.prepared = preview
            let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
            let rows = preview.items.map { item in
                CleanupPreviewRow(id: item.id, url: item.url,
                                  title: lookup[item.id]?.title ?? item.url.lastPathComponent,
                                  logicalSize: item.logicalSize, fileCount: item.fileCount,
                                  blockedReason: item.blockedReason, warnings: item.warnings,
                                  reason: lookup[item.id]?.reason ?? "Selected for cleanup")
            }
            self.selectedPreviewIDs = Set(rows.filter { $0.blockedReason == nil }.map(\.id))
            self.review = CleanupReview(id: preview.id, items: rows,
                                        notes: ["Aster checks each item again before moving it. Changed or unavailable items stay in place."])
        }
    }

    func confirmTrash() {
        // Check at execution as well as in the UI: access may expire or be
        // revoked while the user is reviewing an otherwise valid preview.
        guard license.isPro else {
            errorMessage = "Aster Pro is required to move files to Trash. Your selection is still here."
            return
        }
        guard canConfirm, let preview = prepared, preview.id == review?.id else { return }
        isTrashing = true
        errorMessage = nil
        results = []
        let selected = selectedPreviewIDs
        let candidates = queue
        let protected = runningAppProtection()
        // Keep app data if moving its selected application fails.
        var dependencies: [String: String] = [:]
        for app in candidates where app.kind == "Application" && selected.contains(app.id) {
            guard let bundleID = app.ownerBundleID else { continue }
            for related in candidates where related.id != app.id && related.kind != "Application"
                && (related.ownerBundleID == bundleID || CleanupAppDataPaths.contains(related.url, owner: bundleID)) {
                dependencies[related.id] = app.id
            }
        }
        let revision = UUID()
        self.revision = revision
        operation = Task { [weak self, service] in
            let report = await service.moveToTrash(preview: preview, confirmedIDs: selected,
                                                   protectedURLs: protected, dependencies: dependencies)
            guard let self, self.revision == revision else { return }
            self.isTrashing = false
            let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
            self.results = report.results.map { result in
                CleanupOutcome(id: result.id, url: result.url,
                               title: lookup[result.id]?.title ?? result.url.lastPathComponent,
                               status: CleanupOutcomeStatus(rawValue: result.status.rawValue) ?? .failed,
                               message: result.message, trashURL: result.trashURL)
            }
            let moved = report.results.filter { $0.status == .moved }.map(\.url)
            self.queue.removeAll { candidate in
                moved.contains { candidate.id == $0.path || candidate.id.hasPrefix($0.path + "/") }
            }
            self.invalidatePreview()
            self.statusMessage = report.wasCancelled
                ? "Stopped remaining items. \(moved.count) moved to Trash; see each result below."
                : "\(moved.count) \(moved.count == 1 ? "item" : "items") moved to Trash. Your Trash has not been emptied."
            if !moved.isEmpty { self.didMoveFiles?(moved) }
        }
    }
}

/// The same narrowly identified Library locations used by app inventory. These
/// helpers only construct and compare paths; they never inspect personal files.
private enum CleanupAppDataPaths {
    private static let locations: [(directory: String, suffix: String)] = [
        ("Caches", ""), ("Preferences", ".plist"), ("Application Support", ""),
        ("Containers", ""), ("Logs", ""), ("Saved Application State", ".savedState"),
        ("WebKit", ""), ("HTTPStorages", "")
    ]
    private static var library: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
    }
    static func urls(for identifier: String) -> [URL] {
        guard !identifier.isEmpty, identifier != ".", identifier != "..", !identifier.contains("/") else { return [] }
        var paths = locations.map { location in
            library.appendingPathComponent(location.directory, isDirectory: true)
                .appendingPathComponent(identifier + location.suffix)
        }
        if identifier.caseInsensitiveCompare("com.apple.dt.Xcode") == .orderedSame {
            paths.append(library.appendingPathComponent("Developer/Xcode/DerivedData", isDirectory: true))
        }
        return paths
    }
    static func contains(_ url: URL, owner identifier: String) -> Bool {
        let path = url.path.lowercased()
        return urls(for: identifier).contains { root in
            let base = root.path.lowercased()
            return path == base || path.hasPrefix(base + "/")
        }
    }
    static func owner(of url: URL) -> String? {
        for location in locations {
            let root = library.appendingPathComponent(location.directory, isDirectory: true).path
            guard url.path.lowercased().hasPrefix(root.lowercased() + "/") else { continue }
            let relative = String(url.path.dropFirst(root.count + 1))
            guard var component = relative.split(separator: "/").first.map(String.init) else { continue }
            if !location.suffix.isEmpty {
                guard component.lowercased().hasSuffix(location.suffix.lowercased()) else { continue }
                component.removeLast(location.suffix.count)
            }
            return component.isEmpty ? nil : component
        }
        return nil
    }
}
