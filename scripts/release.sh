#!/bin/bash
# Build Zen for direct distribution: sign with Developer ID (nested Dock
# plug-in first), notarize and staple the app, then package, sign, notarize
# and staple a DMG in dist/.
#
#   scripts/release.sh                  full release
#   scripts/release.sh --skip-notarize  sign and package only
#   scripts/release.sh --adhoc          local dry run: ad-hoc signature, no notarization
#
# Environment:
#   ZEN_SIGNING_IDENTITY  "Developer ID Application: Name (TEAMID)". Defaults to the
#                         only Developer ID Application identity in your keychain.
#   ZEN_NOTARY_PROFILE    notarytool keychain profile (default: zen-notary), created once with
#                         xcrun notarytool store-credentials zen-notary --apple-id <email> --team-id <TEAMID>
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

notarize=1
adhoc=0
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) notarize=0 ;;
        --adhoc) adhoc=1; notarize=0 ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 64 ;;
    esac
done

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# MARK: Signing identity

if [[ $adhoc == 1 ]]; then
    identity="-"
elif [[ -n "${ZEN_SIGNING_IDENTITY:-}" ]]; then
    identity="$ZEN_SIGNING_IDENTITY"
else
    identities="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | sort -u)"
    count="$(printf '%s' "$identities" | grep -c . || true)"
    if [[ $count == 0 ]]; then
        fail "No \"Developer ID Application\" certificate found in your keychain.
Create one at https://developer.apple.com/account/resources/certificates (requires the
Apple Developer Program), install it, then rerun. Use --adhoc for a local dry run."
    elif [[ $count != 1 ]]; then
        fail "Several Developer ID identities found; choose one with ZEN_SIGNING_IDENTITY:
$identities"
    fi
    identity="$identities"
fi
profile="${ZEN_NOTARY_PROFILE:-zen-notary}"

if [[ $notarize == 1 ]] && ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    fail "Notary profile \"$profile\" isn't set up. Create it once with:
  xcrun notarytool store-credentials $profile --apple-id <email> --team-id <TEAMID>
(use an app-specific password from https://account.apple.com), or pass --skip-notarize."
fi

if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "warning: the working tree has uncommitted changes; they will be included in this build." >&2
fi

# MARK: Build

dist="$root/dist"
derived="$root/build/release"
step "Building Release (Apple silicon)"
# Phonon-2's Core ML runtime uses Float16, which isn't available on Intel Macs.
xcodebuild -project zen.xcodeproj -scheme zen -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO -quiet clean build

built="$derived/Build/Products/Release/Zen.app"
[[ -d "$built" ]] || fail "Build product not found at $built"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$built/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$built/Contents/Info.plist")"
name="Zen-$version-$build"

rm -rf "$dist/staging" "$dist/$name.dmg" "$dist/$name-notarize.zip"
mkdir -p "$dist/staging/dmg"
app="$dist/staging/dmg/Zen.app"
ditto "$built" "$app"

# MARK: Sign

sign() {
    local flags=(--force --sign "$identity")
    [[ $identity != "-" ]] && flags+=(--timestamp)
    codesign "${flags[@]}" "$@"
}

step "Signing nested code"
# Sign inside-out: the Dock plug-in (and anything else nested) before the app.
while IFS= read -r -d '' nested; do
    echo "  $(basename "$nested")"
    sign --options runtime "$nested"
done < <(find "$app/Contents" -depth \( -name '*.docktileplugin' -o -name '*.framework' \
    -o -name '*.bundle' -o -name '*.appex' -o -name '*.xpc' -o -name '*.dylib' \) \
    \( -path '*/PlugIns/*' -o -path '*/Frameworks/*' -o -path '*/XPCServices/*' -o -name '*.dylib' \) -print0)

step "Signing Zen.app"
sign --options runtime --entitlements Configuration/Zen.entitlements "$app"

codesign --verify --strict --deep --verbose=2 "$app"
# Capture before matching: with pipefail, `grep -q` closing the pipe early
# would make codesign's SIGPIPE fail the check.
app_info="$(codesign -d --verbose=2 "$app" 2>&1)"
plugin_info="$(codesign -d --verbose=2 "$app/Contents/PlugIns/ZenDockTilePlugin.docktileplugin" 2>&1)"
entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null)"
[[ $app_info =~ flags=.*runtime ]] || fail "Hardened runtime is missing from Zen.app"
[[ $plugin_info =~ flags=.*runtime ]] || fail "Hardened runtime is missing from the Dock plug-in"
[[ $entitlements == *com.apple.security.device.audio-input* ]] \
    || fail "Microphone entitlement is missing; recording would fail under the hardened runtime"

# MARK: Notarize

submit() {
    local file="$1" result="$dist/staging/notary-result.json"
    xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --output-format json > "$result" || true
    local status id
    status="$(plutil -extract status raw -o - "$result" 2>/dev/null || echo unknown)"
    id="$(plutil -extract id raw -o - "$result" 2>/dev/null || echo)"
    if [[ $status != "Accepted" ]]; then
        cat "$result" >&2
        [[ -n $id ]] && xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
        fail "Notarization of $(basename "$file") finished with status: $status"
    fi
    echo "  Accepted ($id)"
}

if [[ $notarize == 1 ]]; then
    step "Notarizing Zen.app (this can take several minutes)"
    ditto -c -k --keepParent "$app" "$dist/$name-notarize.zip"
    submit "$dist/$name-notarize.zip"
    rm -f "$dist/$name-notarize.zip"
    # Stapling lets the first launch pass Gatekeeper even when offline.
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
fi

# MARK: DMG

step "Packaging $name.dmg"
ln -s /Applications "$dist/staging/dmg/Applications"
hdiutil create -volname "Zen" -srcfolder "$dist/staging/dmg" -fs HFS+ -format UDZO -ov -quiet "$dist/$name.dmg"
sign "$dist/$name.dmg"

if [[ $notarize == 1 ]]; then
    step "Notarizing $name.dmg"
    submit "$dist/$name.dmg"
    xcrun stapler staple "$dist/$name.dmg"
    xcrun stapler validate "$dist/$name.dmg"

    step "Checking Gatekeeper"
    spctl --assess --type execute --verbose=2 "$app"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dist/$name.dmg"
fi

rm -rf "$dist/staging"
step "Done"
echo "  $dist/$name.dmg"
echo "  SHA-256 $(shasum -a 256 "$dist/$name.dmg" | cut -d' ' -f1)"
[[ $notarize == 1 ]] || echo "  Not notarized: other Macs will block this DMG. Run without --skip-notarize/--adhoc to release."
