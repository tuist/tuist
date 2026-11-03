#!/usr/bin/env bash
set -euo pipefail

scripts=$(cd "$(dirname "$0")" && pwd)
native=$(cd "$scripts/../.." && pwd)
repo=$(cd "$native/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export FIXTURE_ROOT="$tmp" FIXTURE_LOG="$tmp/events" FIXTURE_FAIL=''
export FIXTURE_SECRET
FIXTURE_SECRET="fixture-private-value-$(uuidgen)"
mkdir -p "$tmp/bin" "$tmp/sdk/bin"
export PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"
bash "$scripts/test-push.sh" --fixture "$tmp/profile-fixture"
export FIXTURE_PROFILE="$tmp/profile-fixture/profile.plist"
export FIXTURE_IDENTITY
FIXTURE_IDENTITY=$(cat "$tmp/profile-fixture/identity")

# Only provider/code-signing commands are fake; plist, copy and ZIP tools are real.
cat > "$tmp/bin/xcrun" <<'BASH'
#!/bin/bash
set -euo pipefail
echo "xcrun $*" >> "$FIXTURE_LOG"
case "$1" in
    vtool) printf 'platform %s\nminos %s\nsdk %s\n' "${FIXTURE_PLATFORM:-MACOS}" "${FIXTURE_MIN:-14.0}" "${FIXTURE_SDK:-26.0}" ;;
    lipo) echo "${FIXTURE_ARCH:-arm64}" ;;
    --sdk) echo 26.0 ;;
    swift-stdlib-tool) : ;;
    notarytool)
        echo "$FIXTURE_SECRET" >&2
        [[ "$FIXTURE_FAIL" != notary-error ]] || exit 1
        if [[ "$FIXTURE_FAIL" = notary ]]; then echo '{"status":"Invalid"}'; else echo '{"status":"Accepted"}'; fi ;;
    stapler)
        [[ "$FIXTURE_FAIL" != staple ]] || exit 1
        if [[ $2 = staple ]]; then touch "$3/Contents/Resources/stapled"; fi ;;
    *) exit 90 ;;
esac
BASH
cat > "$tmp/bin/otool" <<'BASH'
#!/bin/bash
if [[ $1 = -L ]]; then echo '@rpath/Sparkle.framework/Versions/B/Sparkle'; else echo '@executable_path/../Frameworks'; fi
BASH
cat > "$tmp/bin/op" <<'BASH'
#!/bin/bash
set -euo pipefail
[[ $1 = read && $2 = op://tuist/* ]] || exit 90
echo "op $2" >> "$FIXTURE_LOG"
echo "$FIXTURE_SECRET" >&2
[[ "$FIXTURE_FAIL" != vault ]] || exit 1
if [[ $2 = 'op://tuist/Atlas macOS Developer ID/Atlas_macOS_Developer_ID.provisionprofile' ]]; then
    [[ "$FIXTURE_FAIL" != missing-profile ]] || exit 1
    cp "$FIXTURE_PROFILE" "$4"
elif [[ $# = 4 && $3 = --out-file ]]; then echo fixture > "$4"; fi
echo "$FIXTURE_SECRET"
BASH
cat > "$tmp/bin/security" <<'BASH'
#!/bin/bash
set -euo pipefail
echo "security $*" >> "$FIXTURE_LOG"
case "$1" in
    create-keychain|unlock-keychain|import|set-key-partition-list|delete-keychain)
        echo "$FIXTURE_SECRET"
        echo "$FIXTURE_SECRET" >&2 ;;
esac
case "$1" in
    cms) [[ "$FIXTURE_FAIL" != cms ]] || exit 1; cat "$4" ;;
    list-keychains)
        if [[ $# = 3 ]]; then cat "$FIXTURE_ROOT/search-list"; else
            shift 4
            : > "$FIXTURE_ROOT/search-list"
            for entry in "$@"; do printf '    "%s"\n' "$entry" >> "$FIXTURE_ROOT/search-list"; done
        fi ;;
    create-keychain) touch "$4" ;;
    delete-keychain) rm "$2" ;;
    import) [[ "$FIXTURE_FAIL" != import ]] ;;
    find-identity)
        [[ "$FIXTURE_FAIL" != identity ]] || exit 1
        identity=$FIXTURE_IDENTITY
        if [[ "$FIXTURE_FAIL" = mismatched-identity ]]; then identity=0000000000000000000000000000000000000000; fi
        printf '  1) %s "Developer ID Application: Tuist GmbH (U6LC622NKF)"\n' "$identity" ;;
    unlock-keychain) [[ "$FIXTURE_FAIL" != unlock ]] ;;
    set-key-partition-list) [[ "$FIXTURE_FAIL" != partition ]] ;;
    set-keychain-settings) : ;;
    *) echo 'Unexpected security command (including default-keychain mutation)' >&2; exit 90 ;;
esac
BASH
cat > "$tmp/bin/codesign" <<'BASH'
#!/bin/bash
set -euo pipefail
echo "codesign $*" >> "$FIXTURE_LOG"
[[ "$FIXTURE_FAIL" != sign ]] || exit 1
if [[ $1 = --force ]]; then
    [[ " $* " != *' --deep '* ]] || exit 90
    while [[ $# -gt 0 ]]; do
        if [[ $1 = --entitlements ]]; then cp "$2" "$FIXTURE_ROOT/requested.plist"; fi
        shift
    done
elif [[ $1 = --display ]]; then
    case "$2" in
        --extract-certificates=*)
            certificate=good
            if [[ "$FIXTURE_FAIL" = signed-certificate ]]; then certificate=other; fi
            cp "$FIXTURE_ROOT/profile-fixture/$certificate.der" "${2#*=}0" ;;
        --verbose=4)
            team=U6LC622NKF
            if [[ "$FIXTURE_FAIL" = signed-team ]]; then team=XXXXXXXXXX; fi
            echo "TeamIdentifier=$team" ;;
        --entitlements)
            cp "$FIXTURE_ROOT/requested.plist" "$FIXTURE_ROOT/actual.plist"
            case "$FIXTURE_FAIL" in
                signed-environment) /usr/libexec/PlistBuddy -c 'Set :com.apple.developer.aps-environment development' "$FIXTURE_ROOT/actual.plist" ;;
                signed-extra) /usr/libexec/PlistBuddy -c 'Add :com.apple.security.cs.disable-library-validation bool true' "$FIXTURE_ROOT/actual.plist" ;;
            esac
            cat "$FIXTURE_ROOT/actual.plist" ;;
        *) exit 90 ;;
    esac
fi
BASH
cat > "$tmp/bin/spctl" <<'BASH'
#!/bin/bash
echo "spctl $*" >> "$FIXTURE_LOG"
BASH
cat > "$tmp/sdk/bin/generate_appcast" <<'BASH'
#!/bin/bash
set -euo pipefail
key=$(cat)
printf '%s\n' "$key"
printf '%s\n' "$key" >&2
[[ "$FIXTURE_FAIL" != generator ]] || exit 1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --download-url-prefix) prefix=$2; shift 2 ;;
        -o) output=$2; shift 2 ;;
        *) directory=$1; shift ;;
    esac
done
build=${prefix%/}; build=${build##*@}
length=$(stat -f %z "$directory/Atlas-macos.zip")
signature=$(head -c 64 /dev/zero | base64 | tr -d '\n')
case "$FIXTURE_FAIL" in
    signature) signature='' ;;
    malformed-signature) signature=fixture ;;
    length) length=0 ;;
    version) build=1 ;;
    url) prefix=https://example.test/ ;;
esac
item="<item><sparkle:version>$build</sparkle:version><enclosure url=\"${prefix}Atlas-macos.zip\" length=\"$length\" sparkle:edSignature=\"$signature\"/></item>"
if [[ "$FIXTURE_FAIL" = duplicate ]]; then item="$item$item"; fi
cat > "$output" <<XML
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>$item</channel></rss>
XML
mkdir "$directory/old_updates"
mv "$directory/Atlas-macos.zip" "$directory/old_updates/"
BASH
chmod +x "$tmp/bin/"* "$tmp/sdk/bin/generate_appcast"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_private_output() {
    ! grep -Fq "$FIXTURE_SECRET" "$1" || fail 'Public output exposed a vault credential'
    while IFS= read -r password; do
        ! grep -Fq "$password" "$1" || fail 'Public output exposed the generated keychain password'
    done < <(sed -n 's/^security create-keychain -p \([^ ]*\) .*/\1/p' "$FIXTURE_LOG")
}
run_private() {
    if ! "$@" > "$tmp/public.log" 2>&1; then fail 'Signing command failed (private output withheld)'; fi
    assert_private_output "$tmp/public.log"
}
reject() {
    if "$@" > "$tmp/rejection.log" 2>&1; then fail "Unexpected acceptance: $*"; fi
    assert_private_output "$tmp/rejection.log"
}
reset_events() {
    : > "$FIXTURE_LOG"
    printf '    "/Users/fixture/Library/Keychains/login.keychain-db"\n    "/fixture/path with spaces.keychain-db"\n' > "$tmp/search-list"
    cp "$tmp/search-list" "$tmp/original-search-list"
}
check_cleanup() {
    cmp "$tmp/search-list" "$tmp/original-search-list" || fail 'Original search list was not restored'
    ! grep -q 'default-keychain' "$FIXTURE_LOG" || fail 'Default keychain was changed'
    keychain=$(sed -n 's/^security delete-keychain //p' "$FIXTURE_LOG")
    [[ -n "$keychain" && ! -e "$keychain" ]] || fail 'Temporary keychain was not deleted'
}

flat="$tmp/once/Atlas.app"
mkdir -p "$flat/Frameworks/Sparkle.framework/Versions/B/Resources"
cp "$native/macos/Info.plist" "$flat/Info.plist"
cp "$native/macos/Resources/Atlas.icns" "$flat/Atlas.icns"
printf '#!/bin/bash\nexit 0\n' > "$flat/Atlas"
chmod +x "$flat/Atlas"
framework="$flat/Frameworks/Sparkle.framework"
for executable in Sparkle Autoupdate Updater.app/Contents/MacOS/Updater XPCServices/Downloader.xpc/Contents/MacOS/Downloader XPCServices/Installer.xpc/Contents/MacOS/Installer; do
    mkdir -p "$(dirname "$framework/Versions/B/$executable")"
    cp "$flat/Atlas" "$framework/Versions/B/$executable"
done
cp "$flat/Info.plist" "$framework/Versions/B/Resources/Info.plist"
ln -s B "$framework/Versions/Current"
ln -s Versions/Current/Resources "$framework/Resources"
echo resource > "$flat/asset.txt"
bash "$scripts/prepare.sh" "$flat" "$tmp/prepared/Atlas.app"
app="$tmp/prepared/Atlas.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = dev.tuist.atlas ]] || fail 'Production must share the iOS bundle identifier'
[[ -f "$flat/Atlas" && -f "$flat/Info.plist" && -f "$app/Contents/Resources/asset.txt" ]] || fail 'Preparation mutated Once or lost resources'
cmp "$flat/Atlas.icns" "$app/Contents/Resources/Atlas.icns" || fail 'Preparation lost the Atlas icon'
grep -q -- '--sign - --timestamp=none --options 0' "$FIXTURE_LOG" || fail 'Local ad-hoc signing must clear hardened library validation'
! /usr/libexec/PlistBuddy -c 'Print :AtlasPushEnvironment' "$app/Contents/Info.plist" >/dev/null 2>&1 || fail 'Local build claims configured push'
[[ ! -e "$app/Contents/embedded.provisionprofile" ]] || fail 'Local build embeds a push profile'
! /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.aps-environment' "$tmp/requested.plist" >/dev/null 2>&1 || fail 'Local signing claims APNs'
preview="$tmp/preview/AtlasMacOSPreview.app"
ditto "$flat" "$preview"
cp "$native/previews/macos/Info.plist" "$preview/Info.plist"
mv "$preview/Atlas" "$preview/AtlasMacOSPreview"
bash "$scripts/prepare-app.sh" "$preview" "$tmp/preview-runnable/AtlasMacOSPreview.app"
[[ -x "$tmp/preview-runnable/AtlasMacOSPreview.app/Contents/MacOS/AtlasMacOSPreview" ]] || fail 'Preview executable was not preserved'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$tmp/preview-runnable/AtlasMacOSPreview.app/Contents/Info.plist")" = dev.tuist.atlas.macos.preview ]] || fail 'Preview identifier was changed'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$tmp/preview-runnable/AtlasMacOSPreview.app/Contents/Info.plist")" = Atlas.icns ]] || fail 'Preview icon declaration was lost'
cmp "$flat/Atlas.icns" "$tmp/preview-runnable/AtlasMacOSPreview.app/Contents/Resources/Atlas.icns" || fail 'Preview icon was lost'
reject bash "$scripts/bundle.sh" "$tmp/preview-runnable/AtlasMacOSPreview.app" "$tmp/rejected-preview" 1800000000
reject bash "$scripts/prepare.sh" "$flat" "$app"
reject env FIXTURE_MIN=15.0 bash "$scripts/validate.sh" "$app"
reject env FIXTURE_SDK=14.0 bash "$scripts/validate.sh" "$app"
reject env FIXTURE_PLATFORM=IOS bash "$scripts/validate.sh" "$app"
reject env FIXTURE_ARCH=x86_64 bash "$scripts/validate.sh" "$app"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$app/Contents/Info.plist"
reject bash "$scripts/validate.sh" "$app"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Missing.icns' "$app/Contents/Info.plist"
reject bash "$scripts/validate.sh" "$app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile Atlas.icns' "$app/Contents/Info.plist"
mv "$app/Contents/Resources/Atlas.icns" "$tmp/Atlas.icns"
reject bash "$scripts/validate.sh" "$app"
printf 'not an ICNS image' > "$app/Contents/Resources/Atlas.icns"
reject bash "$scripts/validate.sh" "$app"
mv "$tmp/Atlas.icns" "$app/Contents/Resources/Atlas.icns"
/usr/libexec/PlistBuddy -c 'Set :SUFeedURL https://example.test/foreign.xml' "$app/Contents/Info.plist"
reject bash "$scripts/validate.sh" "$app"
cp "$native/macos/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSSupportsLiveActivities bool true' "$app/Contents/Info.plist"
reject bash "$scripts/validate.sh" "$app"
cp "$native/macos/Info.plist" "$app/Contents/Info.plist"
mv "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" "$tmp/Autoupdate"
reject bash "$scripts/validate.sh" "$app"
mv "$tmp/Autoupdate" "$app/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"

reset_events
run_private bash -xv "$scripts/bundle.sh" "$app" "$tmp/release" 1800000000
check_cleanup
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = 1 ]] || fail 'Source version was changed'
ditto -x -k "$tmp/release/Atlas-macos.zip" "$tmp/unzipped"
[[ -f "$tmp/unzipped/Atlas.app/Contents/Resources/stapled" ]] || fail 'Final archive was created before stapling'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$tmp/unzipped/Atlas.app/Contents/Info.plist")" = 1800000000 ]] || fail 'Epoch build was not stamped'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :AtlasPushEnvironment' "$tmp/unzipped/Atlas.app/Contents/Info.plist")" = production ]] || fail 'Signed copy lacks production push metadata'
cmp "$FIXTURE_PROFILE" "$tmp/unzipped/Atlas.app/Contents/embedded.provisionprofile" || fail 'Signed copy lost the authorized profile'
! /usr/libexec/PlistBuddy -c 'Print :AtlasPushEnvironment' "$app/Contents/Info.plist" >/dev/null 2>&1 || fail 'Source push metadata was mutated'
[[ ! -e "$app/Contents/embedded.provisionprofile" ]] || fail 'Source profile was mutated'
(cd "$tmp/release" && shasum -a 256 --check SHASUMS256.txt)
order=$(grep '^codesign --force' "$FIXTURE_LOG" | sed 's/.*signing.keychain-db //')
grep '^codesign --force' "$FIXTURE_LOG" | grep -q -- '--timestamp --options runtime' || fail 'Developer ID signing must use hardened runtime'
[[ "$(sed -n '1p' <<< "$order")" = */Autoupdate ]] || fail 'Autoupdate was not signed first'
[[ "$(sed -n '2p' <<< "$order")" = */Updater.app ]] || fail 'Updater app signing order'
[[ "$(sed -n '3p' <<< "$order")" = */Downloader.xpc ]] || fail 'Downloader signing order'
[[ "$(sed -n '4p' <<< "$order")" = */Installer.xpc ]] || fail 'Installer signing order'
[[ "$(sed -n '5p' <<< "$order")" = */Sparkle.framework ]] || fail 'Framework signing order'
[[ "$(sed -n '6p' <<< "$order")" = *'/Atlas.app' ]] || fail 'Containing app must be signed last'

bash "$scripts/prepare-app.sh" "$tmp/unzipped/Atlas.app" "$tmp/re-ad-hoc/Atlas.app"
[[ ! -e "$tmp/re-ad-hoc/Atlas.app/Contents/embedded.provisionprofile" ]] || fail 'Ad-hoc preparation retained the distribution profile'
! /usr/libexec/PlistBuddy -c 'Print :AtlasPushEnvironment' "$tmp/re-ad-hoc/Atlas.app/Contents/Info.plist" >/dev/null 2>&1 || fail 'Ad-hoc preparation retained push metadata'

for stage in unlock import partition identity mismatched-identity sign signed-certificate signed-team signed-environment signed-extra notary notary-error staple; do
    reset_events
    reject env FIXTURE_FAIL="$stage" bash -xv "$scripts/bundle.sh" "$app" "$tmp/rejected-$stage" 1800000000
    check_cleanup
    [[ ! -e "$tmp/rejected-$stage/Atlas-macos.zip" ]] || fail "Failure $stage produced a release archive"
done
for stage in missing-profile cms; do
    reset_events
    reject env FIXTURE_FAIL="$stage" bash -xv "$scripts/bundle.sh" "$app" "$tmp/rejected-$stage" 1800000000
    ! grep -q 'Developer ID Application Certificate' "$FIXTURE_LOG" || fail 'Bad profile caused a private certificate read'
    ! grep -q 'create-keychain' "$FIXTURE_LOG" || fail 'Bad profile created a keychain'
    cmp "$tmp/search-list" "$tmp/original-search-list" || fail 'Profile failure mutated keychains'
    [[ ! -e "$tmp/rejected-$stage" ]] || fail 'Bad profile produced release output'
done
cp "$FIXTURE_PROFILE" "$tmp/missing-push.plist"
/usr/libexec/PlistBuddy -c 'Delete :Entitlements:com.apple.developer.aps-environment' "$tmp/missing-push.plist"
reset_events
reject env FIXTURE_PROFILE="$tmp/missing-push.plist" bash "$scripts/bundle.sh" "$app" "$tmp/rejected-profile" 1800000000
! grep -q 'Developer ID Application Certificate' "$FIXTURE_LOG" || fail 'Non-Push profile caused a private certificate read'
[[ ! -e "$tmp/rejected-profile" ]] || fail 'Non-Push profile produced release output'

# Match an imported private identity anywhere in the authorized certificate list.
cp "$FIXTURE_PROFILE" "$tmp/multiple-certificates.plist"
/usr/libexec/PlistBuddy -c 'Delete :DeveloperCertificates:0' "$tmp/multiple-certificates.plist"
plutil -insert DeveloperCertificates.0 -data "$(base64 < "$tmp/profile-fixture/other.der")" "$tmp/multiple-certificates.plist"
plutil -insert DeveloperCertificates.1 -data "$(base64 < "$tmp/profile-fixture/good.der")" "$tmp/multiple-certificates.plist"
reset_events
run_private env FIXTURE_PROFILE="$tmp/multiple-certificates.plist" bash -xv "$scripts/bundle.sh" "$app" "$tmp/multiple-certificate-release" 1800000001
check_cleanup
reset_events
run_private bash -xv "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" 1800000000 "$tmp/feed.xml"
[[ -f "$tmp/release/Atlas-macos.zip" && -f "$tmp/feed.xml" ]] || fail 'Appcast generation moved the release archive'
(cd "$tmp/release" && shasum -a 256 --check SHASUMS256.txt)
reset_events
for build in 1799999999 1800000000; do
    reject bash "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" "$build" "$tmp/old-$build.xml" "$tmp/feed.xml"
done
cat > "$tmp/unordered-feed.xml" <<'XML'
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
<item><sparkle:version>1700000000</sparkle:version></item>
<item><sparkle:version>1800001000</sparkle:version></item>
</channel></rss>
XML
reject bash "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" 1800000001 "$tmp/unordered.xml" "$tmp/unordered-feed.xml"
printf '<invalid' > "$tmp/malformed-feed.xml"
reject bash "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" 1800000001 "$tmp/malformed.xml" "$tmp/malformed-feed.xml"
[[ ! -s "$FIXTURE_LOG" ]] || fail 'Rejected previous feed caused a signing-key read'
reject bash "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" 1800000001 "$tmp/feed.xml"
for invalid in signature malformed-signature length version url duplicate vault generator; do
    reject env FIXTURE_FAIL="$invalid" bash -xv "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" 1800000001 "$tmp/invalid-$invalid.xml"
    [[ ! -f "$tmp/invalid-$invalid.xml" ]] || fail "Invalid $invalid feed was accepted"
done

cp "$tmp/release/Atlas-macos.zip" "$tmp/original.zip"
printf 'altered' >> "$tmp/release/Atlas-macos.zip"
reset_events
reject bash "$scripts/appcast.sh" "$tmp/sdk" "$tmp/release" 1800000001 "$tmp/corrupt-archive.xml"
[[ ! -e "$tmp/corrupt-archive.xml" && ! -s "$FIXTURE_LOG" ]] || fail 'Corrupt archive produced a feed or signing-key read'
mv "$tmp/original.zip" "$tmp/release/Atlas-macos.zip"

cat > "$tmp/bin/curl" <<'BASH'
#!/bin/bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
    if [[ $1 = -o ]]; then printf 'altered archive' > "$2"; exit 0; fi
    shift
done
exit 90
BASH
chmod +x "$tmp/bin/curl"
reject bash "$scripts/fetch-sparkle.sh" "$tmp/bad-sdk"
[[ ! -e "$tmp/bad-sdk" ]] || fail 'Checksum mismatch was extracted'
mkdir "$tmp/existing-sdk"
printf 'preserved' > "$tmp/existing-sdk/marker"
reject bash "$scripts/fetch-sparkle.sh" "$tmp/existing-sdk"
[[ $(cat "$tmp/existing-sdk/marker") = preserved ]] || fail 'Existing SDK was changed'

pin=$(sed -n 's/^_SPARKLE_SHA256 = "\([^"]*\)"/\1/p' "$native/modules/sparkle.star")
grep -q "^sha256=$pin$" "$scripts/fetch-sparkle.sh" || fail 'Sparkle tooling/import pins differ'
grep -q 'Tuist App Private Sparkle Key/credential' "$scripts/appcast.sh" || fail 'Signing key reference drift'
grep -q 'needs: \[build, test, test-distribution, lint-rust, lint-swift, lint-kotlin\]' "$repo/.github/workflows/atlas-mobile.yml" || fail 'Release gates missing'
bash "$scripts/test-push.sh"
echo 'macOS packaging fixtures passed (layout, profile/certificate/APNs isolation and preflight, ordered signing, failure cleanup, stapling, appcast copy/signature/epoch and pins)'
