import SwiftUI
import AsterCore

struct ScanDetailsView: View {
    @Environment(LicenseController.self) private var license
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("About this scan").font(.system(size: 23, weight: .medium))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(QuietButtonStyle())
            }
            if state.isScanning, let url = state.scanURL {
                ProPathText(url: url)
            } else if state.hasScannedFolder {
                ProPathText(url: state.snapshot.root.url)
            } else {
                Text(state.isScanning ? "Preparing scan…" : "Choose a folder to begin scanning.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 30) {
                summary("Files", value: state.isScanning ? state.progress?.fileCount.formatted() ?? "—" : state.hasScannedFolder ? state.snapshot.visitedFileCount.formatted() : "—")
                summary("Skipped links", value: state.hasScannedFolder && !state.isScanning ? state.snapshot.skippedLinkCount.formatted() : "—")
                summary("Status", value: state.isScanning ? "Scanning" : state.hasScannedFolder ? state.snapshot.isPartial ? "Partial" : "Complete" : "Not scanned")
            }.padding(.vertical, 8)
            Text("Storage scanning reads metadata only and doesn't follow symbolic links or upload results. Selected items move to Trash only after your review and confirmation. Logical size can differ from allocated disk space, and neither guarantees recoverable space.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            if !state.snapshot.issues.isEmpty {
                SectionEyebrow(text: "Scan notes · \(state.snapshot.issues.count)")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(state.snapshot.issues) { issue in
                            VStack(alignment: .leading, spacing: 5) {
                                ProPathText(url: URL(fileURLWithPath: issue.path))
                                Text(license.isPro ? issue.message : "This location was not fully scanned. You can check access permissions or scan a smaller folder.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(maxHeight: 220).padding(14).background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Button("Full Disk Access settings", action: state.openPrivacySettings).buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
            }
            Text("You choose whether to grant access. Protected locations may still be unavailable.")
                .font(.system(size: 10)).foregroundStyle(Theme.muted)
        }.padding(28).frame(width: 550).background(Theme.background).foregroundStyle(Theme.text)
    }
    private func summary(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionEyebrow(text: label)
            Text(value).font(.system(size: 20, weight: .medium, design: .rounded))
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LicenseController.self) private var license
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "9" }
    var body: some View {
        VStack(spacing: 20) {
            AsterMark(size: 70)
            Text("Aster").font(.system(size: 30, weight: .medium)).tracking(-1)
            Text("A little clarity. A lot of space.").font(.system(size: 14)).foregroundStyle(Theme.secondary)
            Text("Version \(version) · Build \(build)").font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text("Explore your storage. Review what can go.\nBuilt natively for macOS. Your files stay on your device.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Text(license.requiresLicense
                 ? "Payments and license checks use Dodo Payments.\nFile names, paths and scan results are never sent to Dodo."
                 : "All features are free in this version.\nNo account, payment or activation key required.")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Keep exploring") { dismiss() }.buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
        }.padding(42).frame(width: 430).background(Theme.background).foregroundStyle(Theme.text)
    }
}
