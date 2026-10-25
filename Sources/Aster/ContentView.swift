import SwiftUI
import AsterCore

struct ContentView: View {
    @Bindable var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            SidebarView(state: state).frame(width: 205)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Theme.border).frame(height: 1)
                statusBanner
                HStack(spacing: 0) {
                    Group {
                        switch state.section {
                        case .overview: OverviewView(state: state)
                        case .largeFiles: LargeFilesView(state: state)
                        case .cleanup: CleanupWorkspaceView(state: state.cleanup,
                                                            findFiles: { state.showFiles() },
                                                            findApplications: { state.section = .applications; state.category = nil })
                        case .caches: CacheWorkspaceView(state: state.cacheDiscovery, cleanup: state.cleanup)
                        case .applications: ApplicationsWorkspaceView(state: state.inventory, cleanup: state.cleanup)
                        case .leftovers: LeftoversWorkspaceView(state: state.inventory, cleanup: state.cleanup)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if state.section.showsInspector {
                        Rectangle().fill(Theme.border).frame(width: 1)
                        InspectorView(state: state).frame(width: 247)
                    }
                }
                footer
            }
        }
        .frame(minWidth: 1100, minHeight: 740)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .sheet(item: $state.sheet) { sheet in
            if sheet == .scanDetails { ScanDetailsView(state: state) }
            else { AboutView() }
        }
        .sheet(item: Binding(get: { state.cleanup.review }, set: { if $0 == nil { state.cleanup.dismissReview() } })) { _ in
            CleanupReviewSheet(state: state.cleanup)
        }
        .alert("Couldn't finish the scan", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "internaldrive").foregroundStyle(Theme.secondary)
            Text(state.section.showsInspector ? state.snapshot.root.name : "Aster").font(.system(size: 12, weight: .medium)).lineLimit(1)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Theme.muted)
            Text(state.section.rawValue).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            ContactLink()
            if !state.cleanup.queue.isEmpty {
                Button { state.section = .cleanup; state.category = nil } label: {
                    Label("\(state.cleanup.queue.count)", systemImage: "tray")
                }.buttonStyle(QuietButtonStyle()).help("Open cleanup queue")
                    .accessibilityLabel("Cleanup queue, \(state.cleanup.queue.count) \(state.cleanup.queue.count == 1 ? "item" : "items")")
            }
            if state.section != .cleanup {
                Button(action: state.rescan) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(QuietButtonStyle()).help("Refresh this view (⌘R)").disabled(state.isScanning || state.cleanup.isTrashing)
            }
            Button(action: state.chooseFolder) { Label("Scan folder", systemImage: "plus") }
                .buttonStyle(AccentButtonStyle()).accessibilityIdentifier("scan-folder").disabled(state.cleanup.isTrashing)
        }.padding(.horizontal, 26).frame(height: 65)
    }

    @ViewBuilder private var statusBanner: some View {
        if state.isScanning {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scanning \(state.scanURL?.lastPathComponent.isEmpty == false ? state.scanURL!.lastPathComponent : "disk")…")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(state.progress?.fileCount.formatted() ?? "0") files found" + (state.hasScannedFolder ? " · previous results shown until complete" : " · building your storage map"))
                        .font(.system(size: 10)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Button("Cancel", action: state.cancelScan).buttonStyle(QuietButtonStyle())
            }.padding(.horizontal, 26).padding(.vertical, 12).background(Theme.accent.opacity(0.07))
        } else if let notice = state.notice {
            HStack {
                Image(systemName: "info.circle")
                Text(notice).font(.system(size: 11))
                Spacer()
                Button { state.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }.foregroundStyle(Theme.warning).padding(.horizontal, 26).padding(.vertical, 11)
        } else if state.snapshot.isPartial && state.section.showsInspector {
            HStack {
                Image(systemName: "exclamationmark.shield")
                Text("Some locations couldn't be included. These results are partial.").font(.system(size: 11))
                Spacer()
                Button("View details") { state.sheet = .scanDetails }.buttonStyle(.plain).underline()
            }.foregroundStyle(Theme.warning).padding(.horizontal, 26).padding(.vertical, 11)
                .background(Theme.warning.opacity(0.06))
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield").font(.system(size: 10)).foregroundStyle(Theme.mint)
            Text("Your file scans stay on this Mac.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Spacer()
            if state.section.showsInspector {
            Button { state.sheet = .scanDetails } label: {
                HStack(spacing: 5) {
                    Circle().fill(state.snapshot.isPartial ? Color.orange : Theme.mint).frame(width: 4, height: 4)
                    Text(state.hasScannedFolder ? "\(state.snapshot.visitedFileCount.formatted()) files · \(state.snapshot.duration.formatted(.number.precision(.fractionLength(1))))s scan" : "Waiting for your scan to finish")
                    Image(systemName: "info.circle")
                }.font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }.buttonStyle(.plain)
            } else if state.section == .cleanup {
                Text("Your selection · your confirmation").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            } else if state.section == .caches {
                Text("Local caches · review before removal").font(.system(size: 10)).foregroundStyle(Theme.secondary)
            } else {
                Text(state.inventory.isLoading ? "Checking this Mac’s applications…" : "\(state.inventory.result.apps.count) applications · \(state.inventory.result.isComplete ? "scanned locations checked" : "see scan notes")")
                    .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
        }.padding(.horizontal, 24).frame(height: 35)
            .background(Theme.sidebar.opacity(0.6))
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

private struct ContactLink: View {
    private let destination = URL(string: "mailto:shivamrohillaa@gmail.com")!

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 7) {
                Image(systemName: "envelope").font(.system(size: 13)).accessibilityHidden(true)
                Text("Contact me").font(.system(size: 12, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.secondary)
        }
        .buttonStyle(QuietButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .help("Email shivamrohillaa@gmail.com")
        .accessibilityLabel("Contact me")
        .accessibilityHint("Opens your email app to contact Aster support.")
        .accessibilityIdentifier("contact-email")
    }
}
