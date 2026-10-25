# Website distribution: Intel and Apple Silicon

Aster can be distributed from a website without going through the Mac App Store. A public release should use a **Developer ID Application** signature, Hardened Runtime, a secure timestamp, successful Apple notarization and a stapled notarization ticket. These steps do not require App Sandbox and do not grant Full Disk Access or bypass macOS permissions.

The universal release contains `arm64` and `x86_64` slices and requires macOS 14 or later. Intel support therefore applies to Intel Macs capable of running macOS 14 or later. Building both slices verifies compilation and packaging; test actual startup and important workflows on both architectures before launch.

## What the owner must have

1. Active Apple Developer Program membership. A free Apple developer login alone is insufficient for Developer ID distribution.
2. A valid **Developer ID Application** certificate and its corresponding private key in the signing Mac's Keychain. An Apple Development or Mac App Distribution certificate is not a replacement.
3. Notarization credentials stored in a local Keychain profile.
4. A deliberate permanent bundle identifier, version and build number in `Resources/Info.plist`. The script preserves those values; signing does not register a different identifier automatically.

Xcode → Settings → Accounts → select the team → Manage Certificates can create a Developer ID Application identity when the account role permits it. A certificate downloaded without its matching private key cannot sign the app. Keep the private key in Keychain and back it up securely.

List usable signing identities locally:

```sh
security find-identity -v -p codesigning
```

Use Apple's interactive credentials prompt in your own terminal:

```sh
xcrun notarytool store-credentials "Aster-notary"
```

Follow the prompts for the account/team and an app-specific password, or the supported App Store Connect API credential flow. Do not paste passwords or private keys into chat, commit them, or put them into shell arguments. `store-credentials` validates credentials before storing them by default. The release script only references the saved profile name.

## Prepare the signed universal build

From the Aster project directory:

```sh
./scripts/build-app.sh --universal
export ASTER_SIGN_IDENTITY="Developer ID Application: YOUR LEGAL NAME (TEAMID)"
export ASTER_NOTARY_PROFILE="Aster-notary"
./scripts/notarize-release.sh prepare
```

A signing identity's SHA-1 may be used instead of its name. The identity and profile name are not secrets.

The local build is `dist/Aster-universal-local.zip`. It is **not** the website release. `prepare` extracts it into a private temporary staging directory, checks both CPU architectures, clears staging metadata, signs it, verifies the signature and archives the exact bytes to submit. Signing and packaging outside a File Provider-backed workspace avoids Finder metadata invalidating the signature.

The nonsecret `.build/release-state.json` records the artifact hash, staging path and release metadata. Keep the temporary staging directory and state until the release is complete.

## Submit and check Apple's result

Choose **one** upload workflow for a build. The normal `notarytool` route below uses a stored Keychain profile. The optional Xcode-account route described later uses the account already signed in to Xcode, without needing a separate app-specific password in the release commands.

```sh
./scripts/notarize-release.sh submit
./scripts/notarize-release.sh status
```

Submission sends the signed application archive to Apple. It does not upload anything to your website or the App Store. `submit` returns after uploading; it does not wait indefinitely for review. Run `status` again later if Apple reports `In Progress`.

Only the exact submission returning **Accepted** may proceed:

```sh
./scripts/notarize-release.sh finalize
```

`finalize` checks the saved archive's hash and Apple's current status, extracts that archive, staples the ticket and requires these checks to succeed:

- Both `arm64` and `x86_64` architectures.
- Strict code-signature verification with Developer ID, Hardened Runtime and timestamp.
- `stapler validate`.
- Gatekeeper assessment using `spctl --assess --type execute`.
- `syspolicy_check distribution` when available on the signing host.

It then creates the final ZIP, extracts it again and repeats the distribution checks. Only after every required check passes does it publish:

```text
dist/Aster-VERSION-universal.zip
dist/Aster-VERSION-universal.zip.sha256
```

Do not strip extended attributes or re-sign the app after stapling. Do not edit its contents after signing. Upload the completed ZIP itself, without unpacking and recompressing it through another tool.

## Recovery and rejection

- **In Progress:** preserve the saved state and staging directory; check again later. There is no need to upload again.
- **Invalid:** retrieve Apple's diagnostic log, fix the issue and prepare a new signed build. For example, use `xcrun notarytool log SUBMISSION_UUID --keychain-profile "Aster-notary" notarization-log.json`. Logs contain diagnostics, not release approval.
- **An interrupted upload:** inspect the staging directory's `notary-submit.json` before retrying. It may already contain an accepted upload's submission UUID. Recover that ID and profile name in the nonsecret state only after matching it to this upload; otherwise check `notarytool history` and `info` using the saved profile. Do not pair a previous build's accepted UUID with a new archive.
- **Staging files removed or archive hash changed:** the script refuses to continue. Prepare and submit a fresh artifact; an old acceptance does not certify changed bytes.
- **Starting a new release:** move `.build/release-state.json` aside once the previous submission is resolved, bump the release version/build as appropriate and start with `prepare`. The script refuses to overwrite an existing versioned release ZIP.

Never label the local archive “notarized” merely because it is signed or was uploaded to Apple.

## Optional: use the Apple account already signed in to Xcode

Apple's `xcodebuild` distribution workflow can authenticate through Xcode → Settings → Accounts. Its local manual documents this for both `-exportArchive` uploads and `-exportNotarizedApp`. The account must belong to the signing team and have permission to distribute the app.

After `./scripts/notarize-release.sh prepare` succeeds, and **before submitting with notarytool**, run:

```sh
./scripts/notarize-xcode-release.sh prepare
./scripts/notarize-xcode-release.sh submit
```

This alternative takes the exact signed archive recorded by the first script, verifies its SHA-256 and creates an `.xcarchive` wrapper in the existing temporary staging directory. It derives the certificate identity and team from the signed app. The generated export options specify `developer-id`, `upload` and manual signing; no App Store submission is requested. The helper does not automatically create certificates, register app IDs or download provisioning profiles.

The wrapper's archive metadata follows Xcode's archive structure. Manually constructed archives are not a documented stable schema; Xcode must accept this archive before the process can continue. If it rejects the archive format or platform, inspect the log and fix the packaging, or use a conventional Xcode archive target. Do not bypass export or distribution checks.

Separate state is stored in `.build/xcode-release-state.json`. `submit` writes `UploadAttempted` before calling Xcode and logs its combined output to `xcode-release/upload.log` in the staging directory. An interrupted or failed command is not blindly uploaded again; inspect its log and Xcode Organizer status first.

Once Apple has processed the upload:

```sh
./scripts/notarize-xcode-release.sh finalize
```

This runs `xcodebuild -exportNotarizedApp` on the same archive. If notarization is pending or rejected, Xcode exits without an eligible export and the script produces no final ZIP. Check the saved finalization log, and retry later only when appropriate. Xcode's successful notarized export must then pass signature, team, bundle identifier, version, build, both-architecture, stapled-ticket, Gatekeeper and available `syspolicy_check` checks. The generated ZIP is extracted and checked again before publication and SHA-256 generation.

Keep the source state, source ZIP and Xcode archive intact throughout this workflow. If an unexpected Xcode mutation changes the archived app, the script stops for inspection. Do not switch between workflows after uploading or pair an accepted archive with another app build.

## Website and customer experience

Offer one “Download for Mac” link to the final universal ZIP. Display “macOS 14 or later · Apple Silicon and Intel.” The customer downloads, extracts, moves `Aster.app` to Applications and opens it.

A first-open “downloaded from the Internet” confirmation can still appear. Permission prompts, administrator policies, unsupported macOS versions and future Apple security checks still apply. Notarization is not App Store approval, a guarantee of perfect security or a bypass for Gatekeeper.

Test the **browser-downloaded** ZIP on another Mac or a clean test account, including its quarantine and first-open flow. Check scanning, permission explanations, Finder actions and a reviewed cleanup on expendable test files. Do not empty Trash as part of a release smoke test.

The current free app needs no payment or license key. Signing and notarization do not change that policy. Website upload is a separate publication step.

Apple references:

- [Developer ID distribution](https://developer.apple.com/developer-id/)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Safely opening apps on Mac](https://support.apple.com/en-us/102445)
