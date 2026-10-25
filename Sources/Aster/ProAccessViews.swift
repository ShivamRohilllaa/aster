import SwiftUI
import AsterCore

struct ProPathText: View {
    let url: URL
    @Environment(LicenseController.self) private var license
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if license.isPro {
                Text(url.path).textSelection(.enabled)
                    .accessibilityLabel("Path: \(url.path)")
            } else {
                Button { openWindow(id: "license") } label: {
                    Label("Full path · Pro", systemImage: "lock")
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .accessibilityLabel("Unlock full file paths with Aster Pro")
            }
        }
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.secondary)
        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProActionButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void
    @Environment(LicenseController.self) private var license
    @Environment(\.openWindow) private var openWindow

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button {
            if license.isPro { action() }
            else { openWindow(id: "license") }
        } label: {
            Label(license.isPro ? title : "\(title) · Pro",
                  systemImage: license.isPro ? (systemImage ?? "arrow.up.forward.app") : "lock")
        }
        .help(license.isPro ? title : "Available with Aster Pro")
    }
}
