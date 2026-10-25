#!/bin/bash
set -euo pipefail

ASTER_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASTER_CONFIGURATION="release"
ASTER_UNIVERSAL=0
ASTER_ARCHIVE_NAME="Aster-local.zip"
for ASTER_OPTION in "$@"; do
    case "$ASTER_OPTION" in
        --debug) ASTER_CONFIGURATION="debug" ;;
        --universal)
            ASTER_UNIVERSAL=1
            ASTER_ARCHIVE_NAME="Aster-universal-local.zip"
            ;;
        --help|-h)
            printf 'Usage: %s [--debug] [--universal]\n' "$0"
            printf 'Universal builds contain Apple Silicon and Intel slices; all archives still require notarization before public release.\n'
            exit 0
            ;;
        *)
            printf 'Usage: %s [--debug] [--universal]\n' "$0" >&2
            exit 2
            ;;
    esac
done

# Resolve an exact name or SHA-1 fingerprint before spending time on the build.
# find-identity only reports certificates with their corresponding private keys.
if [[ -n "${ASTER_SIGN_IDENTITY:-}" ]]; then
    ASTER_IDENTITY_MATCHES=0
    ASTER_RESOLVED_IDENTITY=""
    ASTER_REQUESTED_FINGERPRINT="$(printf '%s' "$ASTER_SIGN_IDENTITY" | /usr/bin/tr '[:lower:]' '[:upper:]')"
    ASTER_IDENTITIES="$(/usr/bin/security find-identity -v -p codesigning)"
    ASTER_IDENTITY_PATTERN='[[:space:]]([[:xdigit:]]{40})[[:space:]]+"([^"]+)"'
    while IFS= read -r ASTER_IDENTITY_LINE; do
        if [[ "$ASTER_IDENTITY_LINE" =~ $ASTER_IDENTITY_PATTERN ]]; then
            ASTER_IDENTITY_HASH="${BASH_REMATCH[1]}"
            ASTER_IDENTITY_NAME="${BASH_REMATCH[2]}"
            if [[ "$ASTER_SIGN_IDENTITY" == "$ASTER_IDENTITY_NAME" || "$ASTER_REQUESTED_FINGERPRINT" == "$ASTER_IDENTITY_HASH" ]]; then
                if [[ "$ASTER_IDENTITY_NAME" != "Developer ID Application: "* ]]; then
                    printf 'Website distribution requires a Developer ID Application certificate, not %s.\n' "$ASTER_IDENTITY_NAME" >&2
                    exit 1
                fi
                ASTER_IDENTITY_MATCHES=$((ASTER_IDENTITY_MATCHES + 1))
                ASTER_RESOLVED_IDENTITY="$ASTER_IDENTITY_HASH"
            fi
        fi
    done <<< "$ASTER_IDENTITIES"
    if [[ "$ASTER_IDENTITY_MATCHES" -ne 1 ]]; then
        printf 'ASTER_SIGN_IDENTITY must match exactly one valid Developer ID Application identity in your Keychain. Use its full name or SHA-1 fingerprint.\n' >&2
        exit 1
    fi
fi

export CLANG_MODULE_CACHE_PATH="$ASTER_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ASTER_ROOT/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$ASTER_ROOT/.build/cache" "$ASTER_ROOT/.build/configuration" "$ASTER_ROOT/.build/security"
cat "$ASTER_ROOT/Sources/AsterCore/AsterAccessPolicy.swift" "$ASTER_ROOT/scripts/validate-dodo.swift" > "$ASTER_ROOT/.build/validate-access.swift"
ASTER_ACCESS_MODE="$(xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$ASTER_ROOT/.build/validate-access.swift" "$ASTER_ROOT/Resources/DodoConfiguration.json")"
if [[ "$ASTER_ACCESS_MODE" != "free" && "$ASTER_ACCESS_MODE" != "paid" ]]; then
    printf 'Invalid release access policy.\n' >&2
    exit 1
fi
printf 'Access policy: %s\n' "$ASTER_ACCESS_MODE"

ASTER_BUILD_ARGS=(
    --package-path "$ASTER_ROOT"
    --scratch-path "$ASTER_ROOT/.build"
    --cache-path "$ASTER_ROOT/.build/cache"
    --config-path "$ASTER_ROOT/.build/configuration"
    --security-path "$ASTER_ROOT/.build/security"
    --disable-sandbox
    --configuration "$ASTER_CONFIGURATION"
)

if [[ "$ASTER_UNIVERSAL" -eq 1 ]]; then
    ASTER_SLICE_BINARIES=()
    for ASTER_ARCH in arm64 x86_64; do
        # Package.swift supplies the macOS 14 minimum for both architectures.
        # Separate triples keep SwiftPM's intermediate objects architecture-safe.
        ASTER_TRIPLE="$ASTER_ARCH-apple-macosx"
        xcrun swift build "${ASTER_BUILD_ARGS[@]}" --triple "$ASTER_TRIPLE" --product Aster
        ASTER_SLICE_DIR="$(xcrun swift build "${ASTER_BUILD_ARGS[@]}" --triple "$ASTER_TRIPLE" --show-bin-path)"
        /usr/bin/lipo "$ASTER_SLICE_DIR/Aster" -verify_arch "$ASTER_ARCH"
        ASTER_SLICE_BINARIES+=("$ASTER_SLICE_DIR/Aster")
    done
    ASTER_BIN_DIR="$ASTER_ROOT/.build/universal/$ASTER_CONFIGURATION"
    mkdir -p "$ASTER_BIN_DIR"
    /usr/bin/lipo -create "${ASTER_SLICE_BINARIES[@]}" -output "$ASTER_BIN_DIR/Aster"
    /usr/bin/lipo "$ASTER_BIN_DIR/Aster" -verify_arch arm64 x86_64
    printf 'Universal executable: %s\n' "$(/usr/bin/lipo -archs "$ASTER_BIN_DIR/Aster")"
else
    xcrun swift build "${ASTER_BUILD_ARGS[@]}" --product Aster
    ASTER_BIN_DIR="$(xcrun swift build "${ASTER_BUILD_ARGS[@]}" --show-bin-path)"
fi

xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" "$ASTER_ROOT/scripts/generate-icon.swift"
if /usr/bin/iconutil -c icns "$ASTER_ROOT/Resources/AppIcon.iconset" -o "$ASTER_ROOT/.build/AppIcon.icns" 2> "$ASTER_ROOT/.build/iconutil.log"; then
    cp "$ASTER_ROOT/.build/AppIcon.icns" "$ASTER_ROOT/Resources/AppIcon.icns"
else
    printf 'Using generated ICNS container (iconutil unavailable in this environment).\n'
fi

ASTER_STAGE="$(mktemp -d /private/tmp/aster-bundle.XXXXXX)"
trap 'rm -rf "$ASTER_STAGE"' EXIT
ASTER_STAGED_APP="$ASTER_STAGE/Aster.app"
ASTER_APP="$ASTER_ROOT/dist/Aster.app"
mkdir -p "$ASTER_STAGED_APP/Contents/MacOS" "$ASTER_STAGED_APP/Contents/Resources" "$ASTER_ROOT/dist"
cp "$ASTER_BIN_DIR/Aster" "$ASTER_STAGED_APP/Contents/MacOS/Aster"
cp "$ASTER_ROOT/Resources/Info.plist" "$ASTER_STAGED_APP/Contents/Info.plist"
cp "$ASTER_ROOT/Resources/AppIcon.icns" "$ASTER_STAGED_APP/Contents/Resources/AppIcon.icns"
cp "$ASTER_ROOT/LICENSE" "$ASTER_STAGED_APP/Contents/Resources/LICENSE.txt"
if [[ "$ASTER_ACCESS_MODE" == "paid" ]]; then
    cp "$ASTER_ROOT/Resources/DodoConfiguration.json" "$ASTER_STAGED_APP/Contents/Resources/DodoConfiguration.json"
fi
chmod +x "$ASTER_STAGED_APP/Contents/MacOS/Aster"
/usr/bin/plutil -lint "$ASTER_STAGED_APP/Contents/Info.plist"

# File Provider-backed workspaces can attach Finder metadata to freshly created
# bundles. Strip only the two metadata attributes code signing rejects.
/usr/bin/xattr -dr com.apple.FinderInfo "$ASTER_STAGED_APP" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$ASTER_STAGED_APP" 2>/dev/null || true

if [[ -n "${ASTER_SIGN_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --sign "$ASTER_RESOLVED_IDENTITY" --options runtime --timestamp "$ASTER_STAGED_APP"
else
    # Local integrity signature only. This does not notarize the app for distribution.
    /usr/bin/codesign --force --sign - --timestamp=none "$ASTER_STAGED_APP"
fi
/usr/bin/codesign --verify --deep --strict "$ASTER_STAGED_APP"
if [[ "$ASTER_UNIVERSAL" -eq 1 ]]; then
    /usr/bin/lipo "$ASTER_STAGED_APP/Contents/MacOS/Aster" -verify_arch arm64 x86_64
fi
# Archive the verified staging bundle before a File Provider can reattach
# Finder metadata to the workspace copy. The ZIP contains no extended attributes.
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr --noqtn "$ASTER_STAGED_APP" "$ASTER_ROOT/dist/$ASTER_ARCHIVE_NAME"
# Replace the generated app rather than overlaying it, so a previous paid build's
# payment configuration cannot remain in a free bundle.
rm -rf "$ASTER_APP"
/usr/bin/ditto --norsrc --noextattr --noqtn "$ASTER_STAGED_APP" "$ASTER_APP"
/usr/bin/xattr -dr com.apple.FinderInfo "$ASTER_APP" 2>/dev/null || true
/usr/bin/xattr -dr com.apple.ResourceFork "$ASTER_APP" 2>/dev/null || true
printf '\nBuilt %s\nLocal archive (not notarized): %s\n' "$ASTER_APP" "$ASTER_ROOT/dist/$ASTER_ARCHIVE_NAME"
