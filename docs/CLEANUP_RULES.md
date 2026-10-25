# How Aster identifies and reviews cleanup candidates

Aster uses explicit filesystem and app-identity rules. It does not use an AI classifier, an “unused file” score, or file age alone to decide that data should be removed. Scanning and discovery are read-only; moving an item is a separate, confirmed operation.

## 1. Disk scanning and categorization

[`DiskScanner`](../Sources/AsterCore/DiskScanner.swift) enumerates metadata using Foundation and Darwin `lstat`. It records paths, sizes, modification dates and filesystem types. It does not read file contents to judge usefulness.

[`FileCategory.classify`](../Sources/AsterCore/DiskModels.swift) uses known path components and extensions. Examples include `.app` paths for Applications, build/source paths for Developer, media extensions for Media and archive extensions for Archives. Classification is for browsing and visualization; being classified as Developer or Archives does not make a file a cleanup recommendation.

Large-file search filters the completed snapshot by path text, category and minimum logical size. Directories and symlinks are excluded from file search. Size is an ordering/filtering tool, not evidence that a file is unnecessary.

## 2. Caches, logs and developer tools

[`CleanupDiscoveryScanner`](../Sources/AsterCore/CleanupDiscovery.swift) checks existing entries under the current user's `~/Library/Caches` and `~/Library/Logs`, plus explicitly described developer locations. Missing locations are not invented. Custom tool-specific cache paths are not guessed. Partial measurements, Apple-owned data and vendor-managed entries are blocked from the discovery cleanup queue.

The following paths are relative to the user's home directory. These are candidate locations, not proof of inactivity:

| Location | Aster policy | Practical consequence |
| --- | --- | --- |
| `Library/Caches` and `Library/Logs` direct entries | Eligible entries may be reviewed | Quit the associated app and inspect the path; running/Apple/protected data may be blocked. |
| `.npm/_cacache` | Review and Trash | Later installs may need downloads; stop npm tasks first. |
| `.gradle/caches` | Review and Trash | Stop builds/daemons; offline builds and retained build data may be affected. |
| `.cargo/registry/cache` | Review and Trash | Later Rust builds may need to download crates again. |
| `.kube/cache/discovery` | Review and Trash | Future discovery may need cluster connectivity. |
| `.kube/cache/http` | Review and Trash | Subsequent client requests may need network access. |
| `Library/Developer/Xcode/DerivedData` | Review eligible generated data | Quit Xcode/build jobs; preserve any build or test artifacts you need. |
| `.minikube/cache` | Informational only | Use minikube's cache controls; offline images/resources may matter. |
| `Library/Containers/com.docker.docker/Data/log` | Informational only | Manage through Docker Desktop; Aster does not Trash this protected location. |
| `.cache/uv` | Informational only | Use uv's own cache cleanup/prune mechanism. |

The descriptors and vendor documentation links live in [`DeveloperCacheLocations.swift`](../Sources/AsterCore/DeveloperCacheLocations.swift). Generic Library cache discovery can cover other tools when they use those locations. It is not a promise to detect every tool or every customized cache path.

**Docker/Kubernetes scope:** Aster does not run `docker prune`, inspect whether containers/images/volumes are unused, remove Docker VM disks, delete cluster profiles, or propose `.kube/config` and authentication-token caches as disposable data. Installing Docker or Kubernetes is not required to use Aster; only existing supported locations can appear. These discovery exclusions are not a universal blacklist for arbitrary files a user manually selects from disk search.

## 3. Application association and possible leftovers

[`AppInventoryScanner`](../Sources/AsterCore/AppInventory.swift) scans `/Applications` and `~/Applications` by default, with additional locations selectable by the user. It reads verified regular `Contents/Info.plist` files to obtain app identifiers. It does not descend into an app bundle and list its embedded helpers as separate installations.

For a synthetic identifier such as `com.example.editor`, supported associations are exact paths:

| Kind | Example relative to `~/Library` |
| --- | --- |
| Cache | `Caches/com.example.editor` |
| Preferences | `Preferences/com.example.editor.plist` |
| Application Support | `Application Support/com.example.editor` |
| Container | `Containers/com.example.editor` |
| Logs | `Logs/com.example.editor` |
| Saved state | `Saved Application State/com.example.editor.savedState` |
| WebKit data | `WebKit/com.example.editor` |
| HTTP storage | `HTTPStorages/com.example.editor` |

It does not fuzzy-match human-readable app names or sweep Group Containers, launch agents, privileged helpers, system extensions or drivers. Apps with vendor uninstallers may need their own removal process.

Possible leftovers are reported only after a complete inventory. The identifier must have at least three components, must not match an installed app, and must not fall beneath an installed identifier as a helper. An app outside the scanned roots can still use this data. Add all relevant app locations before interpreting leftovers.

Associated data starts unchecked. Multiple detected app copies sharing an identifier keep related-data removal restricted. If selected app data depends on a selected app's removal, the data is kept when that app is not successfully moved.

## 4. Queue, preview and confirmation

[`CleanupState`](../Sources/Aster/CleanupState.swift) owns a session-only queue. Discovery does not automatically populate or execute that queue.

1. The user explicitly queues files, app bundles or eligible discovered entries.
2. `TrashService.prepare` collapses duplicate/overlapping parent-child selections so each selected tree is moved once.
3. Every root is checked, then recursively measured. The preview records logical bytes, included files, warnings, blocked reasons and a metadata fingerprint.
4. Eligible items from this explicitly created queue are selected in the preview; the user can deselect them. This differs from discovery lists, where candidates are not preselected.
5. The user reviews the sheet and confirms a separate macOS-style destructive-action dialog.
6. The service verifies the preview's service identity, age, cancellation/consumption status and confirmed item IDs before execution. Previews expire after 15 minutes and cannot be reused.
7. Protection and metadata checks run again before each move. Changed/unreadable/blocked items are skipped or reported as failures.
8. Only then does the production mover call `FileManager.trashItem(at:resultingItemURL:)`.

The SHA-256 fingerprint covers sorted relative paths and metadata (device/inode, mode, size, timestamps, link count and allocation information). It is **not a hash of file contents**, not malware detection, and not cryptographic proof that no concurrent filesystem change occurred.

## 5. Protected paths and filesystem behavior

[`TrashService`](../Sources/AsterCore/TrashService.swift) protects system trees, shared roots, the home root, essential Library roots, Apple application data, selected running-app data and Aster itself. Protected user trees include Group Containers, Keychains, Mail, Messages and Safari. It blocks Trash and macOS-managed metadata storage.

It also rejects non-local URLs, relative path components, unsafe special entries, selected symlinks, paths through symlink ancestors, mount roots/cross-device trees and unsupported app-bundle fragments. Nested symlinks may move with an otherwise eligible folder; their targets are not traversed or removed. Complete third-party containers may be reviewed where the specific validation rules allow it; arbitrary container internals are not treated as disposable cache.

The application layer supplies running-app protections at review and execution time, using `NSWorkspace` identities. This cannot detect every command-line build or every vendor background process: the displayed instruction to stop relevant work still matters.

## 6. Limits and outcomes

| Operation | Default limit / behavior |
| --- | --- |
| Disk scan | 250,000 nodes; up to 100 recorded issues. |
| Cache discovery | Up to 2,000 direct entries per generic root; 100,000 nodes per measured tree. Partial entries cannot be queued from discovery. |
| App inventory | 50,000 visited application entries and a separate 50,000 related-Library-entry bound. Incomplete discovery suppresses leftovers. |
| Cleanup measurement | 100,000-entry shared budget across selected roots for preview, and a new budget during execution. |
| Preview lifetime | 900 seconds (15 minutes), single use, tied to the creating service. |
| File search display | First 500 matching files; totals still count all matches in the completed snapshot. |

A move reports **moved**, **skipped** or **failed** for each item. Canceling stops remaining work; it does not restore earlier moves. There is no atomic rollback, permanent-delete fallback or automatic Trash emptying. The filesystem is not locked between final validation and the native Trash call, so a concurrent-change race remains possible.

Logical size is not guaranteed recoverable space. APFS sharing, snapshots, compression, sparse files and Trash retention can all affect real disk usage. Aster reports moves without claiming that the displayed number of bytes has been freed.

## Testing the rules

The XCTest suites cover protected roots, symlinks, stale/reused/changed previews, overlapping selections, dependent app-data moves, app identifier matching, incomplete inventories, vendor-managed entries and free-access behavior. Tests use temporary fixtures and injected movers, not the user's personal Trash. See [build and test instructions](BUILD_AND_INSTALL.md#run-tests).
