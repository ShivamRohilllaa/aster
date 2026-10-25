# Architecture and code map

Aster is a Swift Package with a reusable core library and a native macOS executable. The current implementation targets macOS 14+, uses a Swift 6-capable toolchain in Swift 5 language mode, and declares no external package dependencies.

## Modules

| Module / location | Responsibility |
| --- | --- |
| `Sources/AsterCore` | Filesystem models, disk scanner, search, layout, app/cache discovery, reviewed Trash service and optional licensing core. |
| `Sources/Aster` | SwiftUI screens, AppKit integration, main-actor feature state, local persistence and user interaction. |
| `Tests/AsterCoreTests` | Core behavior tested against synthetic models and isolated filesystem fixtures. |
| `Tests/AsterTests` | UI-facing access-policy/state checks. |
| `Resources` | Bundle metadata, generated icon assets and empty optional payment configuration. |
| `scripts` | Build/ZIP generation, icon generation, access-policy validation and optional website notarization. |

`Aster` depends on `AsterCore`. Core services do not depend on SwiftUI views. Some core code is intentionally macOS-specific: Darwin filesystem metadata and `FileManager.trashItem` are not a platform-independent abstraction.

## Patterns actually used

### Observable presentation state (MVVM-style)

`AppState` owns the current disk snapshot, selection, navigation, search inputs and scan tasks. `InventoryState`, `CleanupDiscoveryState` and `CleanupState` own their respective feature workflows. These types use `@Observable` and `@MainActor`; views observe them with `@Bindable` or the SwiftUI environment.

The state objects play a view-model role without enforcing a `ViewModel` suffix. This is a pragmatic presentation/core split, not a full Clean Architecture, Redux or Coordinator framework.

### Service separation and value models

`DiskScanner` reads storage metadata; `DiskSearch` queries a completed snapshot; `AppInventoryScanner` identifies apps and related paths; `CleanupDiscoveryScanner` measures supported cache locations. `DiskNode` and `DiskSnapshot` are value types passed to presentation state. View rendering does not perform filesystem enumeration directly.

`TreemapLayout` is a deterministic geometry function. Given positive finite weights and bounds, it returns proportional rectangles using a squarified layout. Stable ties preserve input order. UI gutters and small-item grouping are applied separately by `StorageMapView`.

### Dependency injection at system boundaries

`TrashService` accepts a `TrashPolicy` and an optional mover closure. Production uses macOS Trash; tests supply a mover operating on isolated fixtures. Licensing similarly uses replaceable client/store boundaries, allowing validation failures and persistence errors to be tested without live payments.

This is targeted injection, not a dependency-injection container. Some native APIs such as `NSWorkspace` are called directly by the application layer.

### Two-stage cleanup with explicit confirmation

`CleanupState` first creates a queue. `TrashService.prepare` produces a preview with a service identifier, timestamp, blocked reasons and recursive metadata fingerprints. The review sheet lets the user choose eligible items, then presents a separate confirmation dialog. Only afterward does `moveToTrash` revalidate and perform individual moves.

This is a preview/execute workflow, not an atomic transaction. There is no all-or-nothing rollback: a later failure or cancellation leaves earlier successful moves in Trash and reports the rest separately.

### Concurrency and stale-result protection

Filesystem work runs in background `Task.detached` workers, with cancellation explicitly forwarded from their callers. Observable UI changes stay on the main actor. Scan/search revision identifiers prevent older work from overwriting newer state. `TrashService` is an actor that manages used-preview bookkeeping; heavy filesystem work runs outside its executor.

Cancellation is cooperative. It stops remaining work when checked; it does not undo work already completed. Neither tasks nor actors lock the filesystem against changes made by other processes.

### Policy and adapter boundaries

`AsterAccessPolicy.requiresLicense = false` enables all current features. The dormant paid flow remains in source for potential future work, but the free app does not require activation or issue Dodo licensing requests. Local bundle validation omits the Dodo configuration from free app bundles.

`KeychainLicenseStore` adapts macOS Keychain for the optional paid flow; it does not contain the developer's signing key. Signing identities are supplied externally to release tools, never embedded in app source.

## Main data flows

### Scan and search

1. `AsterApp` starts a home-folder scan, or honors an explicit `--scan` folder argument.
2. `AppState.startScan` calls `DiskScanner` and displays throttled progress.
3. Foundation enumerates entries; Darwin `lstat` reads metadata without following symbolic links.
4. Directory totals are aggregated from descendants. Allocated-byte estimates deduplicate hard-linked inodes; logical totals count each hard-link name.
5. The completed snapshot feeds category totals, `DiskSearch` and `TreemapLayout`.
6. Views display the results and partial-scan notes. Search operates on the snapshot, not a fresh disk read for every keystroke.

### App and cache inventory

Application discovery reads bundle `Info.plist` identities and compares exact identifiers with supported user-Library paths. Cache discovery checks actual existing locations before reporting their metadata. Neither feature executes vendor uninstallers or guesses that the biggest folder is disposable.

### Cleanup

User selection → queue → measured preview → user review → confirmation → protection/fingerprint checks → native Trash move → per-item report and relevant scan refresh.

See [CLEANUP_RULES.md](CLEANUP_RULES.md) for the exact rules and limits.

## UI design

- `Theme` provides native dynamic colors for dark and light appearances; dark is the default.
- Shared components (`Panel`, button styles, file rows and inspector sections) keep spacing and typography consistent.
- SF Symbols and the system font keep the interface native; the app icon is generated by `scripts/generate-icon.swift`.
- `@AppStorage` persists the appearance preference. Finder actions and folder selection use AppKit.
- Contact is a `mailto:` link. Opening it delegates to the user's email application without automatically sending anything.

## Deliberate limits

There is no content-deduplication engine, background cleanup daemon, privileged helper, app database, auto-updater, cloud scan upload service or required backend. There is no global guarantee that “leftovers” are unused, and cleanup is not a vendor-complete uninstaller. The code includes safeguards, but it cannot make a filesystem preview atomic with a later macOS Trash operation.

Contact: [shivamrohillaa@gmail.com](mailto:shivamrohillaa@gmail.com).
