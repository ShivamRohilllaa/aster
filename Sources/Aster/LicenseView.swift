import SwiftUI
import AsterCore

struct LicenseView: View {
    @Bindable var license: LicenseController

    var body: some View {
        // Keep the paid screen available for a later approved, configured release.
        // The current access policy never presents checkout or activation.
        if license.requiresLicense {
            PaidLicenseView(license: license)
        } else {
            FreeAccessView()
        }
    }
}

private struct FreeAccessView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                AsterMark(size: 58)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Aster, all yours.")
                        .font(.system(size: 29, weight: .medium)).tracking(-0.8)
                    Text("ALL FEATURES FREE")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.mint)
                }
                Spacer()
            }
            Text("Everything is unlocked in this version.\nNo account, payment or activation key required.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 17) {
                feature("chart.pie", title: "See your storage clearly", detail: "Real scans, storage maps and large-file search.")
                feature("folder", title: "Go straight to your files", detail: "Full paths, Copy Path and Reveal in Finder.")
                feature("sparkles", title: "Review what can go", detail: "Supported caches, app uninstalling and possible leftovers.")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.border, lineWidth: 1))
            Label("Every cleanup still needs your review and confirmation. Files move to Trash; Aster never empties it automatically.", systemImage: "hand.raised")
                .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32).frame(width: 600).fixedSize(horizontal: false, vertical: true)
        .background(Theme.background).foregroundStyle(Theme.text)
        .accessibilityIdentifier("free-access-window")
    }

    private func feature(_ symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.accent).frame(width: 24).padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
