import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct AsterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .dark
    var body: some Scene {
        Window("Aster", id: "main") {
            ContentView(state: state)
                .environment(state.license)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: appearance, initial: true) { _, value in
                    NSApp.appearance = NSAppearance(named: value.nativeAppearance)
                }
                .task {
                    let args = ProcessInfo.processInfo.arguments
                    if let index = args.firstIndex(of: "--scan"), args.indices.contains(index + 1) {
                        state.startScan(URL(fileURLWithPath: args[index + 1]))
                    } else if !state.hasScannedFolder && !state.isScanning {
                        state.startScan(FileManager.default.homeDirectoryForCurrentUser, preservingSection: true)
                    }
                    state.inventory.loadIfNeeded()
                }
                .task {
                    guard state.license.requiresLicense else { return }
                    await state.license.refresh()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(3600)) }
                        catch { return }
                        await state.license.refresh()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && state.license.requiresLicense { Task { await state.license.refresh() } }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1340, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…", action: state.chooseFolder).keyboardShortcut("o")
                Button("Scan Home Folder") { state.startScan(FileManager.default.homeDirectoryForCurrentUser) }
                Button("Rescan", action: state.rescan).keyboardShortcut("r")
                Divider()
                Button("Review Cleanup Queue") { state.section = .cleanup; state.category = nil }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Scan Applications") { state.section = .applications; state.category = nil; state.inventory.load() }
                Button("Scan Caches and Logs") { state.section = .caches; state.category = nil; state.cacheDiscovery.load() }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Aster") { state.sheet = .about }
                Button(state.license.requiresLicense ? "Aster Pro & License…" : "All Features Free…") { openWindow(id: "license") }
            }
            CommandGroup(after: .toolbar) {
                Menu("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
            }
        }
        Window("Aster Access", id: "license") {
            LicenseView(license: state.license)
                .environment(state.license)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowResizability(.contentSize)
        Settings {
            AppearanceSettingsView()
                .environment(state.license)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
