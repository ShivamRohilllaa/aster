# Aster

A native macOS storage manager with an interactive storage map, large-file discovery, application inventory, and reviewed cleanup.

**Current release: all implemented features are free for everyone.** No payment, activation key, account, trial expiry, or first-100-user limit is required.

## Requirements

- macOS 14 or later.
- Xcode with its Command Line Tools selected, or a compatible Swift toolchain and macOS SDK.
- No third-party package dependencies or account is required to build locally.

## Build and run

From this directory:

```sh
./scripts/build-app.sh
open dist/Aster.app
```

Use `./scripts/build-app.sh --debug` for a debug bundle. The script builds for the current Mac's architecture, generates the original app icon, and verifies a local ad-hoc signature in a temporary staging directory. It produces `dist/Aster.app` and `dist/Aster-local.zip`. The ZIP excludes extended attributes, preserving a clean bundle when a synced workspace adds Finder metadata. Build products and compiler/module caches stay in `.build` inside this checkout.

Use `./scripts/build-app.sh --universal` to build one app for Apple Silicon and Intel Macs running macOS 14 or later. It compiles both architectures and verifies the merged executable. The resulting `dist/Aster-universal-local.zip` is a local build; follow the [website release guide](docs/WEBSITE_RELEASE.md) to sign, notarize and verify a public download.

You can also open `Package.swift` in Xcode, select the **Aster** executable scheme, and run it on **My Mac**. The packaged `.app` is recommended for checking the Dock icon and macOS folder permissions.

## What is included

- Native SwiftUI/AppKit application for macOS.
- Read-only folder scanning with progress and cancellation.
- A visual storage map and file/category summaries.
- Large-file search and filters.
- File names, full paths, sizes, Copy Path, Reveal in Finder, and storage analysis.
- A cleanup queue with exact-path preview, individual selections, and a separate confirmation before moving anything to macOS Trash.
- Application inventory, removal of complete third-party app bundles, and optional associated-data cleanup.
- Conservative possible-leftover detection based on exact bundle identifiers.
- Real cache and log discovery, with conditional developer-tool cache locations, sizes, file counts, and opt-in cleanup.
- Per-item results, cancellation of remaining moves, and Reveal in Trash when macOS returns the destination.

Aster starts by scanning your home folder and showing live progress. The map, file list, and totals appear when that scan completes. You can cancel the scan or use **Choose folder** to inspect a different folder or disk. Application and leftover results come from the app inventory on your Mac. No demonstration files or invented storage figures are loaded into the app.

Dark appearance is the default. Open **Appearance** in the sidebar, **Aster → Settings…** (⌘,), or **View → Appearance** to switch to Light. The preference is saved on this Mac and applies to all views, the storage map, and review sheets.

## Free access

All implemented features are available without activation: real disk scans, storage maps, large-file search, full paths, Copy Path, Finder actions, cache/app/leftover inventory, reviewed cleanup, supported app removal, and both themes. There is no first-100-user cap, license distribution process, or timed trial.

For questions or feedback, use **Contact me** in the main top bar or email [shivamrohillaa@gmail.com](mailto:shivamrohillaa@gmail.com). The link opens your email app; Aster does not send messages automatically.

The release policy is `AsterAccessPolicy.requiresLicense = false`. Checkout and license activation are disabled, and this free mode does not perform Dodo license requests. Any existing paid-license implementation is retained as dormant source for a possible future release; it is not a requirement for using this build.

See [Free release guide](docs/FREE_RELEASE.md) for the current download and release flow. [Dodo account and product setup](docs/DODO_SETUP.md) is retained only as a future paid-release reference. A paid release would need an explicit product-policy change, approved and configured Dodo integration, and end-to-end verification before being offered to users. No payment or license email has been tested.

## Cleanup workflow

1. Scan a folder. Select a file or folder on the map or in Large files, then choose **Add to cleanup**. The context menu in Large files offers the same action.
2. For app removal, open **Applications** to load the installed app inventory. Select an app and choose which associated items to add to the queue. Associated data starts unchecked. You can also select data while leaving the app unchecked, for example to review its caches. Quit a running app before queuing its removal or data.
3. **Leftovers** lists possible app data whose bundle identifier was not found in the scanned application folders. Nothing is selected automatically. Add any other app folders you use before deciding these files are unwanted.
4. **Caches & logs** measures existing app caches, logs, and supported developer caches. Review the path and caution for each entry, select the ones you want, and add them to your queue. Entries are never preselected.
5. Open **Cleanup → Review for Trash**. Inspect the exact paths, recursively measured logical sizes, warnings, and blocked entries. Deselect anything to keep.
6. Choose **Move … to Trash…**, then confirm in the separate native dialog. Every item is checked again before execution. Changed, protected, inaccessible, or unconfirmed items stay in place. Review the outcome for each item.

Cache discovery uses actual existing locations on each Mac, including the user's `Library/Caches` and `Library/Logs`. This covers many third-party tools without requiring an app-specific rule. Documented developer locations are checked only when present. Cache data can be rebuilt or downloaded again, but may still be needed for current work; size and age alone do not prove an item is unused. Docker-managed storage and credential/configuration files are not offered as disposable cache. Where a tool requires its own cleanup mechanism, its data is informational and cannot be added to the Trash queue.

Additional defaults include npm package cache, Gradle caches, Cargo crate downloads, Xcode Derived Data, and Kubernetes discovery/HTTP caches. Docker Desktop logs, minikube cached resources, and uv cache are measured for visibility with links to their own management guidance. Docker disk images and volumes, `.kube/config`, Kubernetes login-token caches, minikube cluster profiles, and entire tool configuration directories are excluded. Custom tool cache locations are not guessed. Generic cache/log listings are capped at 2,000 direct entries each; individual trees are measured with a 100,000-entry cap. An incomplete entry is clearly marked and unavailable for cleanup, while readable neighbors remain usable.

Aster uses `FileManager.trashItem`; it never falls back to permanent deletion and never empties Trash. Moving items to Trash does not immediately reclaim space. You can inspect moved files in Finder and restore them using Finder where supported. Logical size is not a promise of recovered space.

The queue is held in memory for this session. Overlapping parent/child selections are combined in the preview so they are not moved twice. A preview expires after 15 minutes and cannot be reused. If a selected app cannot be moved, its dependent selected data stays in place. Canceling execution stops remaining work and reports moves that already completed. Storage results are refreshed after successful moves in the scanned folder.

## Application and leftover matching

The default inventory scans `/Applications` and `~/Applications`; additional app folders can be selected. It reads app `Info.plist` identities, skips symlinks, and does not descend into app bundles to treat helper apps as independent installations. Multiple copies of an app remain separate entries; associated data is held back while another detected copy shares the same identifier.

Matches use the exact bundle ID in the current user's Library: `Caches`, `Preferences`, `Application Support`, `Containers`, `Logs`, `Saved Application State`, `WebKit`, and `HTTPStorages`. Group Containers, system extensions, launch agents, privileged helpers, and fuzzy name matches are not included. Possible leftovers are suggestions, not proof that the files are unnecessary. Helper identifiers beneath installed app identifiers are excluded, and incomplete inventories suppress leftover results. App data can include preferences, sessions, and documents; review it carefully. Apps with vendor uninstallers, drivers, or background services may need their own uninstaller.

## Current limits

This free release does not charge users or require a license. It does not empty Trash, perform automatic cleanup, or update itself. Files and scan results stay on the Mac, and the free access policy does not contact Dodo. There is no app account or file upload service.

Cleanup protects system locations, essential Library roots, Apple app bundles, running app bundles, and Aster itself. Direct symlink selections and paths through symlink ancestors are blocked. Links nested inside a selected folder move with that folder without following their targets. A complete preview is required; unreadable folders or selections exceeding 100,000 entries are blocked. Metadata and recursive fingerprints are checked again before each move, but no filesystem lock spans the final macOS Trash call. Avoid editing selected items while cleanup is underway. The app does not request administrator privileges or override macOS permissions.

macOS can restrict Desktop, Documents, Downloads, external volumes, and other folders. Grant the relevant permission when macOS requests it. If you need broader access, review **System Settings → Privacy & Security → Full Disk Access** and explicitly add the packaged Aster app. Aster does not change permissions for you. A scan may be incomplete when some folders cannot be read; permission/error counts should be reviewed before drawing conclusions.

The scanner skips symbolic links to avoid following paths outside the chosen tree or creating cycles. Scanning a folder is not equivalent to measuring every byte used on a volume. APFS clones, shared blocks, snapshots, compression, sparse files, protected storage, and files changing during a scan can produce differences between logical file sizes, allocated-size estimates, Finder totals, and truly reclaimable space. Allocated storage is an estimate, not a promise of space that can be recovered.

Storage scans are capped at 250,000 items and store up to 100 scan notes. Reaching the cap produces clearly marked partial results; choose a smaller folder to inspect the rest. A startup-disk scan excludes `/System/Volumes` and `/Volumes` to avoid duplicate or external-volume counting. Choose an external volume directly to scan it. Search reports the complete match count and displays the first 500 results. The map groups small items to keep rendering responsive; use search and **Show folder on map** to reach their parent folders.

The default ad-hoc signature is for local development. It is not a Developer ID signature, and the build is not notarized. Complete release signing, notarization, and distribution checks before sharing it with customers.

## Signing when preparing a release

Once your Developer ID Application certificate is installed locally, you can choose it explicitly:

```sh
ASTER_SIGN_IDENTITY='Developer ID Application: Your Company (TEAMID)' ./scripts/build-app.sh
```

This enables the hardened runtime and requests a signing timestamp. It uses the identity you provide without retrieving credentials. The bundle identifier is `com.aster.storage.dev`; keep it stable across updates. A public release still needs notarization, distribution testing, a release/update process, and support policies. Free access does not replace these release steps. The build script does not submit the app to Apple or publish anything.

This repository contains source code, not signed release binaries or personal signing material. Build and verify a new release from this source using the [website release guide](docs/WEBSITE_RELEASE.md) and your own Developer ID identity. Previous release archives do not contain the current contact-link change.

## Source layout

- `Sources/AsterCore`: filesystem scanning, storage models, app inventory, and the preview/revalidation/Trash service.
- `Sources/Aster`: macOS application and interface.
- `Tests`: automated checks and synthetic fixtures, excluded from the shipping app. Cleanup tests inject a mover that only touches isolated temporary fixtures; they do not use your personal Trash.
- `Resources`: bundle metadata and original generated icon assets.
- `scripts/generate-icon.swift`: vector drawing source for the icon.
- `scripts/build-app.sh`: local application bundling and signing.
- `scripts/notarize-release.sh`: staged Developer ID signing, notarization and verification for website releases.
- `scripts/notarize-xcode-release.sh`: notarization using the Apple account already signed in to Xcode.

To run tests with caches inside the checkout:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --scratch-path "$PWD/.build" \
  --cache-path "$PWD/.build/cache" \
  --config-path "$PWD/.build/configuration" \
  --security-path "$PWD/.build/security" --disable-sandbox
```
