import Foundation
@testable import AsterCore

// Test-only synthetic inventory. These app names and paths are never compiled
// into the application or shown to users.
extension AppInventoryResult {
    static var demo: AppInventoryResult {
        let root = URL(fileURLWithPath: "/Aster Demo", isDirectory: true)
        func relativePath(_ kind: AppRelatedKind, _ identifier: String) -> String {
            switch kind {
            case .caches: return "Caches/\(identifier)"
            case .preferences: return "Preferences/\(identifier).plist"
            case .applicationSupport: return "Application Support/\(identifier)"
            case .containers: return "Containers/\(identifier)"
            case .logs: return "Logs/\(identifier)"
            case .savedState: return "Saved Application State/\(identifier).savedState"
            case .webKit: return "WebKit/\(identifier)"
            case .httpStorage: return "HTTPStorages/\(identifier)"
            }
        }
        func related(_ identifier: String, _ kinds: [AppRelatedKind]) -> [AppRelatedFile] {
            kinds.map { kind in
                AppRelatedFile(url: root.appendingPathComponent("Library/" + relativePath(kind, identifier)),
                               kind: kind, reason: "Sample data — no real file exists at this path.", ownerBundleIdentifier: identifier)
            }
        }
        let apps = [
            InstalledApp(name: "Orbit", bundleIdentifier: "com.example.orbit", bundleURL: root.appendingPathComponent("Applications/Orbit.app"), relatedFiles: related("com.example.orbit", [.caches, .preferences, .applicationSupport])),
            InstalledApp(name: "Forma", bundleIdentifier: "com.example.forma", bundleURL: root.appendingPathComponent("Applications/Forma.app"), relatedFiles: related("com.example.forma", [.caches, .containers])),
            InstalledApp(name: "Studio", bundleIdentifier: "com.example.studio", bundleURL: root.appendingPathComponent("Applications/Studio.app"), relatedFiles: related("com.example.studio", [.logs, .savedState, .webKit]))
        ]
        let leftovers = [LeftoverGroup(bundleIdentifier: "com.example.old-editor", files: related("com.example.old-editor", [.caches, .preferences]))]
        return AppInventoryResult(apps: apps, leftovers: leftovers, isDemo: true)
    }
}
