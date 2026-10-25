# Aster: current free release

All implemented Aster features are free for everyone in the current release. Users do not need to pay, sign up, submit a Mac ID, request a license key, or activate anything. There is no first-100-user limit or timed trial.

## What users receive

- Real disk and folder scanning, storage maps, categories, and large-file search.
- Full file paths, Copy Path, and Show/Reveal in Finder.
- Installed-app, supported-cache/log, developer-cache, and possible-leftover discovery.
- Reviewed cleanup, supported third-party app removal, and opt-in removal of supported associated data.
- Dark and light appearance.

These are the app's implemented features, not a promise to remove every kind of cache or uninstall every trace of every application. Detected files are real; possible leftovers and caches still need the user's judgment.

## Download and use

1. Download a verified release ZIP from your distributor and extract it, or build locally using the README instructions.
2. Move `Aster.app` into Applications, open it, and grant the macOS folder permissions needed for the chosen scan.
3. Scan a folder or disk and inspect the real results.
4. Add chosen items to the cleanup queue.
5. Review exact paths, warnings, and selections, then confirm the move to Trash.

There is no checkout or activation step. The website can use **Download for Free** as its main call to action and explain that all current features are included. Remove current purchase prompts, license-key instructions, and first-100-user claims from release messaging.

The main top bar includes **Contact me**, which opens the user's email app addressed to [shivamrohillaa@gmail.com](mailto:shivamrohillaa@gmail.com). Contacting support is optional and does not affect feature access. Aster does not send email automatically.

Do not advertise “free forever” or paid future upgrades unless that policy is explicitly decided. The current policy grants free access to the features in this release.

## Safety and privacy stay in place

Making the app free does not bypass any filesystem checks or cleanup confirmations. Protected locations, running apps, incomplete scans, unsupported data, and unsafe selections stay restricted. Associated app data starts unchecked.

Aster moves confirmed selections using macOS Trash. It never falls back to permanent deletion and never empties Trash automatically. Disk space is not immediately reclaimed by moving files to Trash; the user controls when Trash is emptied.

File names, file paths, and scan results stay on the Mac. Current free mode does not make Dodo checkout or licensing requests. No customer account or license server is needed to use this release.

## Access policy and future payments

`AsterAccessPolicy.requiresLicense = false` is the current access policy. All access checks must respect it, including file paths, Finder actions, app removal, and Trash execution. Checkout UI and automatic license checks remain inactive in this mode.

The existing Dodo-related source is retained for a possible later paid release. Retaining source does not mean payments are active. No first-100-key issuer, private signing-key store, or issued-license ledger is needed for this release.

Before any later paid release:

1. Decide and clearly disclose the new feature, pricing, and existing-user policy.
2. Obtain Dodo account approval and configure the actual product and entitlements.
3. Review the access-policy and interface changes together.
4. Test checkout, email delivery, activation, invalid keys, refunds, and offline behavior end to end.
5. Publish accurate pricing and policies, then distribute a separately verified release.

[DODO_SETUP.md](DODO_SETUP.md) preserves the earlier integration instructions as a future reference. Do not switch paid access on merely because a product ID has been added.

## Preparing the public download

This repository contains source code only. Build a new universal app from the current source and complete the [signing and notarization workflow](WEBSITE_RELEASE.md) with your own Developer ID identity before distributing it. No release archive is certified by this source-only repository.

Universal builds target Apple Silicon and Intel Macs running macOS 14 or later. Test the final download on both architectures and publish working support and privacy links alongside it.

The default build script creates a local ad-hoc-signed build. Files named `Aster-local.zip` and `Aster-universal-local.zip` are development artifacts. Existing archives from earlier builds do not include the current contact-link change.

Free access needs no payment credentials, license keys, or backend secrets in the app bundle. Public release signing and notarization still require the owner's Apple Developer setup.
