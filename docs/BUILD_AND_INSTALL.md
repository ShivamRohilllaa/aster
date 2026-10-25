# Build, install and package Aster

This guide starts from source and separates a local development build from a verified website download. The app is distributed as a normal `.app` bundle inside a ZIP; it does not need a privileged installer.

## 1. Prepare the Mac

- Use macOS 14 or later.
- Install Xcode or compatible Command Line Tools providing a Swift 6-capable toolchain and macOS SDK. The package compiles in Swift 5 language mode.
- Install/enable Git. Python 3 is needed by the notarization helper scripts; `/usr/bin/python3` is the interpreter those scripts invoke.
- For the full release workflow, select the intended Xcode installation and complete its first-launch setup.

Check the active tools:

```sh
xcode-select -p
xcrun swift --version
xcrun --show-sdk-path
git --version
```

If needed, install Command Line Tools with `xcode-select --install`. If you have several Xcode versions, select the correct one before building, for example `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` for Xcode installed there. Complete any license/component setup through Xcode. No Apple Developer membership is required for the default local build.

## 2. Get the source

Copy this repository's HTTPS clone URL from GitHub's **Code** button. Replace `REPOSITORY_URL` below with that URL:

```sh
git clone REPOSITORY_URL aster
cd aster
```

For Xcode editing, choose **File → Open** and select `Package.swift` (or open the package folder). Select the Aster scheme and **My Mac** destination. The scripts below are the reproducible path for creating the final `.app` directory and ZIP; there is no checked-in `.xcodeproj` to generate first.

## 3. Build for the current Mac

```sh
./scripts/build-app.sh
```

Outputs:

```text
dist/Aster.app
dist/Aster-local.zip
```

The script validates the access policy, builds the executable, generates the icon, copies bundle metadata/resources and the MIT notice (`Contents/Resources/LICENSE.txt`), creates a clean staging bundle, applies an ad-hoc integrity signature and verifies it. Free builds omit the optional Dodo configuration from the app bundle.

For faster development builds:

```sh
./scripts/build-app.sh --debug
```

If you have exported `ASTER_SIGN_IDENTITY` in your shell, that explicitly requests Developer ID signing. Use `env -u ASTER_SIGN_IDENTITY ./scripts/build-app.sh` when you intend a local ad-hoc build instead. The script never exports a signing key.

## 4. Open the app locally

```sh
open dist/Aster.app
```

The app scans the current user's home directory and shows progress. Use **Scan folder** (`⌘O`) to select a smaller folder. An explicit startup scan can also be requested:

```sh
open -n dist/Aster.app --args --scan "$HOME/Downloads"
```

`-n` starts a new instance; quit it when finished to avoid confusing it with another running build. Scanning reads metadata; it does not automatically clean the selected folder.

If a sync/File Provider service modifies bundle metadata after signing, use the already-created ZIP in a local temporary directory:

```sh
ASTER_RUN_DIR="$(mktemp -d)"
ditto -x -k dist/Aster-local.zip "$ASTER_RUN_DIR"
codesign --verify --deep --strict "$ASTER_RUN_DIR/Aster.app"
open "$ASTER_RUN_DIR/Aster.app"
```

Use `Aster-universal-local.zip` instead if that is the archive you built. Preserve the ZIP's bytes when transferring a verified release. Do not disable Gatekeeper or strip quarantine globally to work around a distribution problem.

## 5. Build for Apple Silicon and Intel

```sh
./scripts/build-app.sh --universal
lipo -archs dist/Aster.app/Contents/MacOS/Aster
```

The architecture check should list `arm64` and `x86_64` (order can differ). Output:

```text
dist/Aster.app
dist/Aster-universal-local.zip
```

This ZIP contains one app with both executable slices. A user does not have to choose between separate Intel and Apple Silicon installers. The minimum macOS version remains 14 on both architectures.

Compiling both slices does not replace testing on both architectures. Rosetta execution on Apple Silicon is useful additional coverage but is not a physical Intel-Mac test.

## Run tests

From the repository root:

```sh
swift test
```

To keep compiler/package caches inside the checkout:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --scratch-path "$PWD/.build" \
  --cache-path "$PWD/.build/cache" \
  --config-path "$PWD/.build/configuration" \
  --security-path "$PWD/.build/security" --disable-sandbox
```

`--disable-sandbox` here concerns the SwiftPM build sandbox; it does not bypass macOS privacy permissions or Aster cleanup restrictions. Test filesystem changes are confined to disposable fixtures through injected movers.

## 6. Prepare a signed website release

The default ZIP is **not notarized**. For public distribution, use your own Apple Developer membership, **Developer ID Application** identity/private key in your Mac's Keychain, and notarization credentials. Do not put any of these credentials in Git.

1. Choose and review the bundle identifier, version and build in `Resources/Info.plist`. Keep an established product identifier stable across updates; use your own identifier when distributing a separate fork.
2. Build a universal local ZIP.
3. Supply your signing identity through `ASTER_SIGN_IDENTITY` and use `./scripts/notarize-release.sh prepare`.
4. Store credentials using Apple's interactive `xcrun notarytool store-credentials` flow and supply the profile name through `ASTER_NOTARY_PROFILE`.
5. Submit with `./scripts/notarize-release.sh submit`, check with `status`, and proceed only after Apple reports **Accepted**.
6. Run `./scripts/notarize-release.sh finalize` to staple, verify and package the accepted app.
7. Test the actual downloaded archive on a separate Mac/test account, including permissions and first-open behavior.

Follow [WEBSITE_RELEASE.md](WEBSITE_RELEASE.md) for exact commands, the optional Xcode-account workflow, failure recovery and verification gates. Choose one notarization workflow for a build; do not mix acceptance records from different binaries.

The final output naming convention is:

```text
dist/Aster-VERSION-universal.zip
dist/Aster-VERSION-universal.zip.sha256
```

These files are ignored by Git. Source changes do not update or re-notarize an older ZIP automatically. Signed apps contain a public signer identity; removing source references does not anonymize an already-distributed signed binary. Private signing keys are not included in signed apps.

## 7. Optional DMG packaging

A ZIP is sufficient for direct website downloads. A DMG can provide a familiar drag-to-Applications window, but creating a disk image does not notarize its contents. Begin with a **verified, stapled release app**, not a local ad-hoc build.

For a local packaging example, replace `PATH_TO_VERIFIED_ASTER_APP` with that app's path:

```sh
ASTER_DMG_ROOT="$(mktemp -d)"
ditto PATH_TO_VERIFIED_ASTER_APP "$ASTER_DMG_ROOT/Aster.app"
ln -s /Applications "$ASTER_DMG_ROOT/Applications"
hdiutil create -volname Aster -srcfolder "$ASTER_DMG_ROOT" \
  -format UDZO -ov dist/Aster.dmg
hdiutil verify dist/Aster.dmg
```

The current repository scripts produce ZIPs; they do not automate DMG signing/notarization. A public DMG needs its own distribution checks and any required outer-container signing/notarization. No `.pkg` installer or administrator helper is implemented or required by Aster.

## 8. End-user installation

For a verified release ZIP:

1. Download and extract the ZIP.
2. Move `Aster.app` to **Applications**.
3. Open it and follow normal macOS first-open checks.
4. Choose a folder and grant only the access you want. For broader access, review **System Settings → Privacy & Security → Full Disk Access**.
5. Inspect findings, add chosen items to the queue, review, and confirm any Trash operation.

Uninstalling Aster itself normally means quitting it and moving its app bundle to Trash. It has no privileged background helper. macOS may retain preferences and permission records separately.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Toolchain or SDK errors | Confirm `xcode-select -p`, `xcrun swift --version` and Xcode first-launch setup. |
| Missing permission / partial scan | Review scan notes, select a smaller accessible folder, or explicitly grant the relevant macOS permission. |
| App blocked after a web download | Confirm that the distributor supplied the verified Developer ID-signed, notarized artifact. A locally built ZIP is not that artifact. |
| Signature fails after a synced-folder copy | Extract the original ZIP to a clean local directory and verify it again. Never modify a stapled app bundle in place. |
| Signing identity not found | Check that the correct Developer ID Application identity and its private key exist in the signing Mac's Keychain. |
| Different sizes from Finder | Logical size, allocation estimates and APFS recoverable space are different measurements. |

Contact: [shivamrohillaa@gmail.com](mailto:shivamrohillaa@gmail.com).
