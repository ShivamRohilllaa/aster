import AppKit
import SwiftUI
import AsterCore

/// Dormant paid UI. Presented only when AsterAccessPolicy.requiresLicense is enabled
/// in a future build after merchant approval, configuration and purchase verification.
struct PaidLicenseView: View {
    @Bindable var license: LicenseController
    @State private var licenseKey = ""
    @State private var showsDeactivationConfirmation = false
    @FocusState private var keyFieldFocused: Bool
    private var trimmedKey: String { licenseKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canActivate: Bool { license.configuration != nil && !trimmedKey.isEmpty && !license.isBusy }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 15) {
                    AsterMark(size: 54)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Aster Pro").font(.system(size: 27, weight: .medium)).tracking(-0.7)
                        Text("Understand your storage. Choose what can go.")
                            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                }
                if license.configuration?.environment == .test {
                    notice("TEST MODE · No real payment", symbol: "testtube.2", color: Theme.warning)
                }
                HStack(alignment: .top, spacing: 14) {
                    tier("FREE", title: "See the whole picture.", features: ["Disk scans & storage map", "Large-file search", "Cache, app & leftover discovery", "Cleanup previews"])
                    tier("PRO", title: "Choose what can go.", features: ["Everything in Free", "Full paths & Finder actions", "Reviewed cleanup & app uninstall", "Selected app data & leftovers"])
                }
                if !license.isPro {
                    if let checkoutURL = license.checkoutURL {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("One-time purchase. One Mac.").font(.system(size: 13, weight: .medium))
                                Text("For the purchased version of Aster.").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button("View price & buy") { NSWorkspace.shared.open(checkoutURL) }
                                .buttonStyle(AccentButtonStyle()).accessibilityIdentifier("license-buy-pro")
                        }
                    } else {
                        notice("Purchases and activation are not configured for this build.", symbol: "info.circle", color: Theme.secondary)
                    }
                }
                if license.hasSavedLicense {
                    savedLicense
                } else {
                    activationForm
                }
                if let error = license.errorMessage {
                    notice(error, symbol: "exclamationmark.circle", color: Theme.warning)
                } else if let message = license.message {
                    notice(message, symbol: "info.circle", color: Theme.secondary)
                }
                notice("Every cleanup requires review and confirmation. Files move to Trash; Aster never empties it.", symbol: "hand.raised", color: Theme.muted)
            }.padding(30)
        }
        .frame(minWidth: 680, minHeight: 650).background(Theme.background).foregroundStyle(Theme.text)
        .onDisappear { licenseKey = "" }.accessibilityIdentifier("license-window")
        .confirmationDialog("Deactivate Aster Pro on this Mac?", isPresented: $showsDeactivationConfirmation, titleVisibility: .visible) {
            Button("Deactivate this Mac", role: .destructive) { Task { await license.deactivate() } }
            Button("Keep license", role: .cancel) {}
        } message: {
            Text("Free scanning and previews remain available.")
        }
    }

    private var activationForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Already have a license?").font(.system(size: 15, weight: .medium))
            Text("Enter the key from your purchase email to activate this Mac.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            HStack(spacing: 10) {
                SecureField("Paste your license key", text: $licenseKey)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .focused($keyFieldFocused).disabled(license.isBusy).onSubmit { activate() }
                    .padding(12).background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.border, lineWidth: 1))
                    .accessibilityIdentifier("license-key-field")
                Button(license.isBusy ? "Activating…" : "Activate license", action: activate)
                    .buttonStyle(AccentButtonStyle()).disabled(!canActivate)
                    .accessibilityIdentifier("license-activate")
            }
        }.padding(19).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private var savedLicense: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(license.isPro ? "Activated on this Mac" : "Your license needs a check")
                .font(.system(size: 17, weight: .medium))
            if let offlineUntil = license.offlineUntil {
                Text("Offline access until \(offlineUntil.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            HStack {
                Button("Verify now") { Task { await license.refresh() } }
                    .buttonStyle(QuietButtonStyle()).disabled(license.isBusy || license.configuration == nil)
                Spacer()
                Button("Deactivate this Mac…") { showsDeactivationConfirmation = true }
                    .buttonStyle(QuietButtonStyle()).disabled(license.isBusy || license.configuration == nil)
            }
        }.padding(20).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func tier(_ name: String, title: String, features: [String]) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(name).font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 16, weight: .medium))
            ForEach(features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }.padding(19).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(color).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func activate() {
        guard canActivate else { return }
        let key = trimmedKey
        Task {
            await license.activate(key)
            if license.isPro && license.errorMessage == nil {
                licenseKey = ""
                keyFieldFocused = false
            }
        }
    }
}
