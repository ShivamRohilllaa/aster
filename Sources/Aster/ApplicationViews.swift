import AppKit
import SwiftUI
import AsterCore

struct ApplicationsWorkspaceView: View {
    @Environment(LicenseController.self) private var license
    @Bindable var state: InventoryState
    @Bindable var cleanup: CleanupState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InventoryPageHeader(state: state, title: "Apps, with a little perspective.",
                                subtitle: "See each application and choose exactly what belongs in your cleanup queue.")
            InventoryScanNotice(state: state)
            HStack(alignment: .top, spacing: 18) {
                applicationList.frame(width: 285)
                if let app = state.selectedApp {
                    applicationDetail(app)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    InventoryEmptyState(symbol: "app.dashed", title: state.hasLoaded ? "Find a familiar face." : "Scan applications",
                                        message: !state.hasLoaded
                                        ? (state.isLoading ? "Checking the applications installed on this Mac…" : "Scan your applications to see what’s installed on this Mac.")
                                        : (state.query.isEmpty ? "No removable applications were found in the checked folders." : "No applications match this search."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(26)
        .onAppear { state.loadIfNeeded() }
        .onChange(of: state.query) { _, _ in
            if !state.filteredApps.contains(where: { $0.id == state.selectedAppID }) {
                state.selectedAppID = state.filteredApps.first?.id
            }
        }
        .accessibilityIdentifier("applications-workspace")
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Find an application…", text: $state.query)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .accessibilityLabel("Search applications")
                    .accessibilityIdentifier("applications-search")
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Clear application search")
                }
            }.padding(15)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                SectionEyebrow(text: "Applications")
                Spacer()
                Text(state.filteredApps.count.formatted()).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 15).padding(.top, 15).padding(.bottom, 9)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(state.filteredApps) { app in
                        Button { state.selectedAppID = app.id } label: {
                            HStack(spacing: 11) {
                                InventoryAppIcon(app: app, size: 32)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(app.name).font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.text).lineLimit(1)
                                    Text(state.isRunning(app) ? "Running" : app.bundleIdentifier)
                                        .font(.system(size: 9)).foregroundStyle(state.isRunning(app) ? Theme.warning : Theme.muted)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                if state.selectedAppID == app.id {
                                    Circle().fill(Theme.accent).frame(width: 4, height: 4)
                                }
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(state.selectedAppID == app.id ? Theme.accent.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .help(license.isPro ? app.bundleURL.path : app.name)
                            .accessibilityLabel("\(app.name)\(license.isPro ? ", \(app.bundleURL.path)" : "")\(state.isRunning(app) ? ", running" : "")")
                            .accessibilityIdentifier("application-\(license.isPro ? app.id : app.bundleIdentifier)")
                    }
                }.padding(.horizontal, 7).padding(.bottom, 10)
            }
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    private func applicationDetail(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    HStack(alignment: .center, spacing: 15) {
                        InventoryAppIcon(app: app, size: 55)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(app.name).font(.system(size: 23, weight: .medium)).tracking(-0.6).textSelection(.enabled)
                            Text(app.bundleIdentifier).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.secondary).textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                    }
                    if state.isRunning(app) {
                        InventoryInlineNote(symbol: "pause.circle", text: "Quit \(app.name) before adding this application or its data to the cleanup queue.", color: Theme.warning)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        SectionEyebrow(text: "The application")
                        HStack(alignment: .top, spacing: 11) {
                            Toggle("Include application bundle", isOn: $state.includeSelectedApp)
                                .toggleStyle(.checkbox).labelsHidden()
                                .disabled(state.isRunning(app) || isBusy)
                                .accessibilityLabel("Include \(app.name) application bundle")
                                .accessibilityIdentifier("application-include-bundle")
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text("Application bundle").font(.system(size: 12, weight: .medium))
                                    Spacer()
                                    if cleanup.contains(app.bundleURL) { queuedBadge }
                                }
                                InventoryPath(url: app.bundleURL)
                                Text("Its size will be checked in the cleanup review.")
                                    .font(.system(size: 10)).foregroundStyle(Theme.muted)
                            }
                        }.padding(14)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.border, lineWidth: 1))
                    }
                    relatedFiles(for: app)
                }.padding(20)
            }.scrollIndicators(.hidden)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(applicationCandidates(app).count) ready to add")
                        .font(.system(size: 11, weight: .medium))
                    Text("Related data is always your choice.")
                        .font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Button {
                    state.refreshRunningApplications()
                    let candidates = applicationCandidates(app)
                    for candidate in candidates { cleanup.add(candidate) }
                    state.statusMessage = candidates.isEmpty
                        ? "No new items were added. Check the selection and close the application if it’s running."
                        : "Added \(candidates.count) \(candidates.count == 1 ? "item" : "items") to your cleanup queue. Review the queue before anything moves."
                } label: {
                    Label("Add to cleanup queue", systemImage: "plus")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(applicationCandidates(app).isEmpty || isBusy)
                .opacity(applicationCandidates(app).isEmpty || isBusy ? 0.45 : 1)
                .accessibilityIdentifier("application-add-to-queue")
            }.padding(18).background(Theme.sidebar.opacity(0.5))
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .background(Theme.panel.opacity(0.34), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder private func relatedFiles(for app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: "Related data")
                Spacer()
                Text("OPT IN").font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(Theme.accent)
            }
            if state.hasOtherCopy(app) {
                InventoryInlineNote(symbol: "square.on.square", text: "Another copy of this application is installed. Related data stays out of this selection because both copies may use it.", color: Theme.secondary)
            } else if app.relatedFiles.isEmpty {
                Text("No exact matches found in the checked Library locations.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3).padding(.vertical, 9)
            } else {
                Text("These locations match the app’s identifier. They may contain preferences or personal data; select only what you intend to remove.")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
                ForEach(app.relatedFiles) { file in
                    InventoryRelatedRow(file: file, selected: state.selectedRelatedIDs.contains(file.id),
                                        disabled: state.isRunning(app) || isBusy,
                                        queued: cleanup.contains(file.url), toggle: { state.toggleRelated(file.id) })
                }
            }
        }
    }

    private var isBusy: Bool { state.isLoading || cleanup.isPreparing || cleanup.isTrashing }

    private func applicationCandidates(_ app: InstalledApp) -> [CleanupCandidate] {
        guard !state.isRunning(app) else { return [] }
        var candidates: [CleanupCandidate] = []
        if state.includeSelectedApp {
            candidates.append(CleanupCandidate(url: app.bundleURL, title: app.name,
                                               reason: "Application bundle explicitly selected for review.",
                                               kind: "Application", symbol: "app.fill", logicalSize: nil,
                                               ownerBundleID: state.identifier(for: app)))
        }
        if !state.hasOtherCopy(app) {
            for file in app.relatedFiles where state.selectedRelatedIDs.contains(file.id) {
                candidates.append(inventoryCandidate(file))
            }
        }
        return candidates.filter { !cleanup.contains($0.url) }
    }
}

struct LeftoversWorkspaceView: View {
    @Bindable var state: InventoryState
    @Bindable var cleanup: CleanupState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InventoryPageHeader(state: state, title: "What’s left behind.",
                                subtitle: "Possible app leftovers, brought into view for a closer look.")
            InventoryScanNotice(state: state)
            InventoryInlineNote(symbol: "info.circle", text: "Possible leftovers are suggestions. An app may live outside the folders checked, and these files may contain settings or personal data. Nothing is selected automatically.", color: Theme.secondary)
            if !state.hasLoaded {
                InventoryEmptyState(symbol: "sparkle.magnifyingglass", title: "Scan applications",
                                    message: state.isLoading
                                    ? "Checking installed applications and their Library locations on this Mac…"
                                    : "Scan installed applications before reviewing possible leftover data.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.result.leftovers.isEmpty {
                InventoryEmptyState(symbol: "sparkle.magnifyingglass", title: state.result.isComplete ? "A little less to wonder about." : "More context is needed.",
                                    message: state.result.isComplete
                                    ? "No possible leftovers were found in the checked locations."
                                    : "Leftover suggestions are hidden because some app or Library locations couldn’t be checked. Review the scan notes and scan again.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 19) {
                        ForEach(state.result.leftovers) { group in
                            leftoverGroup(group)
                        }
                    }.padding(.bottom, 5)
                }.scrollIndicators(.hidden)
            }
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(leftoverCandidates.count) ready to add")
                        .font(.system(size: 12, weight: .medium))
                    Text("Exact sizes and paths are checked again in the cleanup review.")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    state.refreshRunningApplications()
                    let candidates = leftoverCandidates
                    for candidate in candidates { cleanup.add(candidate) }
                    state.statusMessage = candidates.isEmpty
                        ? "No new items were added. Review the selection and running applications."
                        : "Added \(candidates.count) \(candidates.count == 1 ? "item" : "items") to your cleanup queue. Review the queue before anything moves."
                } label: {
                    Label("Add selected to queue", systemImage: "plus")
                }
                .buttonStyle(AccentButtonStyle()).disabled(leftoverCandidates.isEmpty || isBusy)
                .opacity(leftoverCandidates.isEmpty || isBusy ? 0.45 : 1)
                .accessibilityIdentifier("leftovers-add-to-queue")
            }.padding(.top, 13)
                .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
        .padding(26)
        .onAppear { state.loadIfNeeded() }
        .accessibilityIdentifier("leftovers-workspace")
    }

    private func leftoverGroup(_ group: LeftoverGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 18, weight: .light)).foregroundStyle(Theme.accent)
                    .frame(width: 39, height: 40)
                    .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title).font(.system(size: 15, weight: .medium)).textSelection(.enabled)
                    Text(group.bundleIdentifier).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.secondary).textSelection(.enabled)
                }
                Spacer()
                Text("POSSIBLE LEFTOVERS").font(.system(size: 8, weight: .semibold)).tracking(1)
                    .foregroundStyle(Theme.warning)
            }
            if !group.caution.isEmpty {
                Text(group.caution).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineSpacing(3)
            }
            if state.isRunning(ownerBundleIdentifier: group.bundleIdentifier) {
                InventoryInlineNote(symbol: "pause.circle", text: "An application using this identifier is running. Quit it before adding this data to the queue.", color: Theme.warning)
            }
            ForEach(group.files) { file in
                InventoryRelatedRow(file: file, selected: state.selectedLeftoverIDs.contains(file.id),
                                    disabled: isBusy || state.isRunning(ownerBundleIdentifier: file.ownerBundleIdentifier),
                                    queued: cleanup.contains(file.url), toggle: { state.toggleLeftover(file.id) })
            }
        }.padding(19).background(Theme.panel.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    private var isBusy: Bool { state.isLoading || cleanup.isPreparing || cleanup.isTrashing }

    private var leftoverCandidates: [CleanupCandidate] {
        guard state.result.isComplete else { return [] }
        return state.result.leftovers.flatMap(\.files)
            .filter { state.selectedLeftoverIDs.contains($0.id)
                && !state.isRunning(ownerBundleIdentifier: $0.ownerBundleIdentifier)
                && !cleanup.contains($0.url) }
            .map { inventoryCandidate($0) }
    }
}

private struct InventoryPageHeader: View {
    @Environment(LicenseController.self) private var license
    @Bindable var state: InventoryState
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 27, weight: .medium)).tracking(-0.8)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(3)
                if license.isPro {
                    Text("Locations: \(state.locationsDescription)")
                        .font(.system(size: 9)).foregroundStyle(Theme.muted)
                        .lineLimit(2).textSelection(.enabled)
                } else {
                    Text("Standard application folders and any folders you choose.")
                        .font(.system(size: 9)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    Button(action: state.chooseApplicationsFolder) {
                        Image(systemName: "folder.badge.plus")
                    }.buttonStyle(QuietButtonStyle()).disabled(state.isLoading)
                        .help("Check an additional applications folder")
                        .accessibilityLabel("Scan an additional applications folder")
                    Button(action: state.load) {
                        Label(state.hasLoaded ? "Scan again" : "Scan applications", systemImage: state.hasLoaded ? "arrow.clockwise" : "magnifyingglass")
                    }.buttonStyle(AccentButtonStyle()).disabled(state.isLoading)
                        .accessibilityIdentifier("inventory-scan-applications")
                }
                Text(state.isLoading ? "CHECKING THIS MAC" : state.hasLoaded ? "\(state.result.apps.count.formatted()) APPLICATIONS CHECKED" : "READY TO SCAN")
                    .font(.system(size: 8, weight: .semibold)).tracking(1)
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct InventoryScanNotice: View {
    @Environment(LicenseController.self) private var license
    @Bindable var state: InventoryState
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if state.isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking applications and related files…")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Cancel", action: state.cancel).buttonStyle(.plain)
                        .font(.system(size: 11)).foregroundStyle(Theme.accent)
                }.padding(12).background(Theme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
            } else if let error = state.errorMessage {
                InventoryInlineNote(symbol: "exclamationmark.circle", text: license.isPro ? error : "Application discovery couldn’t finish. Try again or check access to the folders you selected.", color: Theme.warning)
            } else if let status = state.statusMessage {
                InventoryInlineNote(symbol: "info.circle", text: status, color: Theme.secondary)
            }
            if !state.result.warnings.isEmpty {
                DisclosureGroup {
                    if license.isPro {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(state.result.warnings.enumerated()), id: \.offset) { _, warning in
                                    Text(warning).font(.system(size: 10)).foregroundStyle(Theme.secondary)
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(.top, 7)
                        }.frame(maxHeight: 130)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Some locations could not be fully checked. Possible leftovers stay hidden when discovery is incomplete.")
                                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            ProActionButton("View detailed scan notes", systemImage: "text.alignleft") {}
                                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                        }.padding(.top, 7)
                    }
                } label: {
                    Text("Scan notes · \(state.result.warnings.count)")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.warning)
                }
                .padding(.horizontal, 3)
            }
        }
    }
}

private struct InventoryRelatedRow: View {
    @Environment(LicenseController.self) private var license
    let file: AppRelatedFile
    let selected: Bool
    let disabled: Bool
    let queued: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Toggle("Include \(file.title)", isOn: Binding(get: { selected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox).labelsHidden().disabled(disabled)
                .accessibilityLabel(license.isPro ? "Include \(file.title), \(file.url.path)" : "Include \(file.title)")
                .accessibilityIdentifier("inventory-include-\(license.isPro ? file.id : file.ownerBundleIdentifier + "-" + file.kind.rawValue)")
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(file.title).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 10)
                    if queued { queuedBadge }
                    else { Text(file.kind.title).font(.system(size: 9)).foregroundStyle(Theme.muted) }
                }
                InventoryPath(url: file.url)
                Text(file.reason).font(.system(size: 10)).foregroundStyle(Theme.secondary).lineSpacing(3)
                if !file.caution.isEmpty {
                    Text(file.caution).font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(3)
                }
            }
        }
        .padding(13).background(selected ? Theme.accent.opacity(0.055) : Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent.opacity(0.22) : Theme.border, lineWidth: 1))
    }
}

private struct InventoryAppIcon: View {
    let app: InstalledApp
    let size: CGFloat
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "app.fill").font(.system(size: size * 0.61, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: size * 0.22))
            }
        }.frame(width: size, height: size)
            .task(id: app.id) {
                icon = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
            }
            .accessibilityHidden(true)
    }
}

private struct InventoryPath: View {
    let url: URL
    var body: some View {
        ProPathText(url: url)
    }
}

private struct InventoryInlineNote: View {
    let symbol: String
    let text: String
    let color: Color
    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(color).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct InventoryEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: symbol).font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Theme.accent.opacity(0.7))
            Text(title).font(.system(size: 19, weight: .medium)).tracking(-0.4)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
                .multilineTextAlignment(.center).frame(maxWidth: 390)
        }.padding(25)
    }
}

private var queuedBadge: some View {
    Label("Queued", systemImage: "checkmark").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.mint)
}

private func inventoryCandidate(_ file: AppRelatedFile) -> CleanupCandidate {
    CleanupCandidate(url: file.url, title: file.title, reason: file.reason + " " + file.caution,
                     kind: file.kind.title, symbol: "folder", logicalSize: nil,
                     ownerBundleID: file.ownerBundleIdentifier)
}
