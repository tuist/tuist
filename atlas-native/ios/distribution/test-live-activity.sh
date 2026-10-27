#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
modules=$(cd "$root/../../modules" && pwd)
plist=/usr/libexec/PlistBuddy
[[ -x "$plist" ]] || { echo 'These fixtures require macOS plist tools' >&2; exit 1; }
source "$root/live-activity.sh"
source "$root/share.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/atlas live activity.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/Atlas.app"
activity="$app/PlugIns/AtlasLiveActivity.appex"
share="$app/PlugIns/AtlasShare.appex"
profile="$work/profile.plist"
host_profile="$work/host-profile.plist"
entitlements="$work/activity-entitlements.plist"
future=$(date -u -v+2d '+%Y-%m-%dT%H:%M:%SZ')
identity=9B79E9B8396E56510F653C48F5AFEF97A959B373
passed=0

fail() { echo "$*" >&2; exit 1; }
pass() { passed=$((passed + 1)); echo "Passed $1"; }
deny() {
    local name=$1
    shift
    if ( "$@" ) > "$work/error.log" 2>&1; then
        fail "$name unexpectedly succeeded"
    fi
    pass "$name"
}

fixture_profile() {
    cat > "$profile" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Entitlements</key><dict>
<key>application-identifier</key><string>U6LC622NKF.dev.tuist.atlas.live-activity</string>
<key>com.apple.developer.team-identifier</key><string>U6LC622NKF</string>
<key>get-task-allow</key><false/>
<key>aps-environment</key><string>production</string>
<key>keychain-access-groups</key><array><string>U6LC622NKF.*</string></array>
<key>com.apple.developer.associated-domains</key><array><string>applinks:atlas.tuist.dev</string></array>
<key>com.apple.security.application-groups</key><array><string>group.dev.tuist.atlas.share</string></array>
</dict>
<key>ProvisionedDevices</key><array><string>device-one</string><string>device-two</string></array>
<key>ExpirationDate</key><date>${1:-$future}</date>
<key>DeveloperCertificates</key><array>
<data>YW5vdGhlciBjZXJ0aWZpY2F0ZQ==</data>
<data>Zml4dHVyZSBkaXN0cmlidXRpb24gY2VydGlmaWNhdGUsIG5vdCBhIHJlYWwgaWRlbnRpdHk=</data>
</array></dict></plist>
PLIST
}

fixture_bundle() {
    rm -rf "$app"
    mkdir -p "$activity/_CodeSignature"
    cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.tuist.atlas</string>
<key>CFBundleVersion</key><string>1792920000</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
</dict></plist>
PLIST
    cp "$root/../LiveActivity/Info.plist" "$activity/Info.plist"
    "$plist" -c 'Set :CFBundleIdentifier dev.tuist.atlas.live-activity' "$activity/Info.plist"
    printf '#!/bin/sh\nexit 0\n' > "$activity/AtlasLiveActivity"
    chmod +x "$activity/AtlasLiveActivity"
    printf 'fixture signature\n' > "$activity/_CodeSignature/CodeResources"
    mkdir -p "$share"
    cp "$root/../Share/Info.plist" "$share/Info.plist"
    printf '#!/bin/sh\nexit 0\n' > "$share/AtlasShare"
    chmod +x "$share/AtlasShare"
}

mkdir -p "$work/bin"
cat > "$work/bin/fixture-tool" <<'BASH'
#!/bin/bash
set -euo pipefail
case ${0##*/} in
    xcrun)
        if [[ $1 = vtool ]]; then
            printf 'platform %s\n' "${FIXTURE_PLATFORM:-IOS}"
        elif [[ $1 = swift-stdlib-tool ]]; then
            shift
            {
                printf 'scan'
                while [[ $# -gt 0 ]]; do
                    if [[ $1 = --scan-executable ]]; then printf '\t%s' "$2"; shift; fi
                    shift
                done
                printf '\n'
            } >> "$FIXTURE_CALLS"
        else
            exit 1
        fi ;;
    codesign)
        target=${!#}
        action=verify
        entitlements=''
        deep=false
        while [[ $# -gt 0 ]]; do
            case $1 in
                --force) action=sign ;;
                --deep) deep=true ;;
                --entitlements) entitlements=$2; shift ;;
            esac
            shift
        done
        [[ $action != sign || $deep = false ]] || exit 1
        printf '%s\t%s\t%s\n' "$action" "$target" "$entitlements" >> "$FIXTURE_CALLS"
        [[ $target != "${FAIL_SIGN_TARGET:-}" ]] ;;
    ditto)
        [[ ${FAIL_COPY:-false} = false ]] || exit 1
        exec /usr/bin/ditto "$@" ;;
    op)
        printf '%s\n' "$2" >> "$FIXTURE_OP_CALLS"
        case $2 in
            'op://tuist/Atlas App Ad Hoc/Atlas_App_Ad_Hoc.mobileprovision') cp "$FIXTURE_HOST_PROFILE" "$4" ;;
            'op://tuist/Atlas Live Activity Ad Hoc/Atlas_Live_Activity_Ad_Hoc.mobileprovision') cp "$FIXTURE_ACTIVITY_PROFILE" "$4" ;;
            'op://tuist/Atlas Share Ad Hoc/Atlas_Share_Ad_Hoc.mobileprovision') cp "$FIXTURE_SHARE_PROFILE" "$4" ;;
            *) echo 'Unexpected private credential read' >&2; exit 1 ;;
        esac ;;
    security)
        [[ $1 = cms ]] || exit 1
        cat "${!#}" ;;
    *) exit 1 ;;
esac
BASH
chmod +x "$work/bin/fixture-tool"
for tool in xcrun codesign ditto op security; do ln -s fixture-tool "$work/bin/$tool"; done
export PATH="$work/bin:$PATH" FIXTURE_CALLS="$work/calls.log" FIXTURE_OP_CALLS="$work/op.log"

fixture_profile
cp "$profile" "$host_profile"
validate_live_activity_profile "$profile" "$host_profile" "$identity"
pass 'certificate matching includes non-first entries'

for name in wrong-app wrong-team development expired enterprise empty-devices scalar-devices missing-device wrong-certificate empty-certificates; do
    fixture_profile
    case $name in
        wrong-app) "$plist" -c 'Set :Entitlements:application-identifier U6LC622NKF.dev.tuist.atlas' "$profile" ;;
        wrong-team) "$plist" -c 'Set :Entitlements:com.apple.developer.team-identifier OTHERTEAM' "$profile" ;;
        development) "$plist" -c 'Set :Entitlements:get-task-allow true' "$profile" ;;
        expired) fixture_profile '2000-01-01T00:00:00Z' ;;
        enterprise) "$plist" -c 'Add :ProvisionsAllDevices bool true' "$profile" ;;
        empty-devices) "$plist" -c 'Delete :ProvisionedDevices' -c 'Add :ProvisionedDevices array' "$profile" ;;
        scalar-devices) "$plist" -c 'Delete :ProvisionedDevices' -c 'Add :ProvisionedDevices string device-one' "$profile" ;;
        missing-device) "$plist" -c 'Delete :ProvisionedDevices:1' "$profile" ;;
        wrong-certificate) "$plist" -c 'Delete :DeveloperCertificates:1' "$profile" ;;
        empty-certificates) "$plist" -c 'Delete :DeveloperCertificates' -c 'Add :DeveloperCertificates array' "$profile" ;;
    esac
    deny "$name" validate_live_activity_profile "$profile" "$host_profile" "$identity"
done

for key in ExpirationDate ProvisionedDevices DeveloperCertificates Entitlements; do
    fixture_profile
    "$plist" -c "Delete :$key" "$profile"
    deny "missing $key" validate_live_activity_profile "$profile" "$host_profile" "$identity"
done

fixture_bundle
validate_live_activity_bundle "$app"
pass 'device extension identity and WidgetKit extension point'
for key in CFBundleIdentifier CFBundleExecutable CFBundlePackageType; do
    fixture_bundle
    "$plist" -c "Set :$key wrong" "$activity/Info.plist"
    deny "wrong $key" validate_live_activity_bundle "$app"
done
fixture_bundle
"$plist" -c 'Set :NSExtension:NSExtensionPointIdentifier wrong' "$activity/Info.plist"
deny 'wrong extension point' validate_live_activity_bundle "$app"
fixture_bundle
# shellcheck disable=SC2016 # The child shell expands its positional arguments.
deny 'simulator cannot be distributed to devices' env FIXTURE_PLATFORM=IOSSIMULATOR \
    bash -c 'source "$1"; validate_live_activity_bundle "$2"' fixture "$root/live-activity.sh" "$app"
mkdir "$app/PlugIns/Other.appex"
deny 'unexpected bundled extension' validate_live_activity_bundle "$app"

fixture_bundle
printf 'fixture provisioning profile\n' > "$work/fixture.mobileprovision"
prepare_live_activity_distribution "$app" "$work/fixture.mobileprovision" "$entitlements"
cmp "$work/fixture.mobileprovision" "$activity/embedded.mobileprovision"
[[ $("$plist" -c 'Print :CFBundleVersion' "$activity/Info.plist") = 1792920000 ]]
[[ $("$plist" -c 'Print :CFBundleShortVersionString' "$activity/Info.plist") = 0.1.0 ]]
[[ $(plutil -extract application-identifier raw "$entitlements") = U6LC622NKF.dev.tuist.atlas.live-activity ]]
[[ $("$plist" -c 'Print :com.apple.developer.team-identifier' "$entitlements") = U6LC622NKF ]]
[[ $(plutil -extract get-task-allow raw "$entitlements") = false ]]
for key in aps-environment keychain-access-groups com.apple.developer.associated-domains; do
    if "$plist" -c "Print :$key" "$entitlements" >/dev/null 2>&1; then fail "Host entitlement leaked: $key"; fi
done
pass 'distribution copy versions, profile and isolated extension entitlements'

inner="$app/Frameworks/Outer.framework/Frameworks/Inner.framework"
mkdir -p "$inner"
printf 'fixture library\n' > "$inner/libFixture.dylib"
: > "$FIXTURE_CALLS"
sign_live_activity_distribution "$app" fixture-identity "$work/temporary keychain" "$work/host-entitlements.plist" "$entitlements"
{
    printf 'scan\t%s\t%s\n' "$app/Atlas" "$activity/AtlasLiveActivity"
    printf 'sign\t%s\t\n' "$inner/libFixture.dylib" "$inner" "$app/Frameworks/Outer.framework"
    printf 'sign\t%s\t%s\n' "$activity" "$entitlements"
    printf 'verify\t%s\t\n' "$activity"
    printf 'sign\t%s\t%s\n' "$app" "$work/host-entitlements.plist"
    printf 'verify\t%s\t\n' "$app"
} > "$work/expected-signing.log"
diff -u "$work/expected-signing.log" "$FIXTURE_CALLS"
pass 'both executables scanned and nested contents signed before extension and host'

: > "$FIXTURE_CALLS"
export FAIL_SIGN_TARGET="$activity"
deny 'extension signing failure' sign_live_activity_distribution "$app" fixture-identity \
    "$work/temporary keychain" "$work/host-entitlements.plist" "$entitlements"
unset FAIL_SIGN_TARGET
if grep -Fqx "$(printf 'sign\t%s\t%s' "$app" "$work/host-entitlements.plist")" "$FIXTURE_CALLS"; then
    fail 'Host signed after extension signing failed'
fi
pass 'extension failure prevents host signing'

source_bundle="$work/built/AtlasLiveActivity.appex"
mkdir -p "$(dirname "$source_bundle")"
ditto "$activity" "$source_bundle"
printf 'obsolete\n' > "$activity/obsolete.txt"
mkdir "$app/PlugIns/Sibling.bundle"
bash "$modules/embed-widget.sh" "$source_bundle" "$activity"
[[ ! -e "$activity/obsolete.txt" && -x "$activity/AtlasLiveActivity" && -d "$app/PlugIns/Sibling.bundle" ]]
diff -r "$source_bundle" "$activity"
pass 'embedding preserves source, complete signature tree, executable and siblings'
deny 'embedding cannot copy onto itself' bash "$modules/embed-widget.sh" "$activity" "$activity"
deny 'embedding cannot escape PlugIns' bash "$modules/embed-widget.sh" "$source_bundle" "$app/AtlasLiveActivity.appex"
cp "$activity/Info.plist" "$work/before.plist"
deny 'failed copy' env FAIL_COPY=true bash "$modules/embed-widget.sh" "$source_bundle" "$activity"
cmp "$work/before.plist" "$activity/Info.plist"
for leftover in "$app"/PlugIns/.AtlasLiveActivity.*; do [[ ! -e "$leftover" ]] || fail 'Temporary embedding tree leaked'; done
pass 'failed embedding preserves installed extension and cleans temporary files'

bundle_root="$work/isolated bundle"
mkdir -p "$bundle_root/ios/distribution" "$bundle_root/.once/out/AtlasIOSDevice"
for script in bundle keychain associated-domains push live-activity share; do cp "$root/$script.sh" "$bundle_root/ios/distribution/"; done
ditto "$app" "$bundle_root/.once/out/AtlasIOSDevice/Atlas.app"
rmdir "$bundle_root/.once/out/AtlasIOSDevice/Atlas.app/PlugIns/Sibling.bundle"
"$plist" -c 'Set :CFBundleIdentifier wrong' "$bundle_root/.once/out/AtlasIOSDevice/Atlas.app/PlugIns/AtlasLiveActivity.appex/Info.plist"
: > "$FIXTURE_OP_CALLS"
deny 'bundle validation precedes all credential reads' bash "$bundle_root/ios/distribution/bundle.sh"
[[ ! -s "$FIXTURE_OP_CALLS" ]] || fail 'Read credentials before bundle validation'
"$plist" -c 'Set :CFBundleIdentifier dev.tuist.atlas.live-activity' "$bundle_root/.once/out/AtlasIOSDevice/Atlas.app/PlugIns/AtlasLiveActivity.appex/Info.plist"
fixture_profile
cp "$profile" "$host_profile"
"$plist" -c 'Set :Entitlements:application-identifier U6LC622NKF.dev.tuist.atlas' "$host_profile"
"$plist" -c 'Set :Entitlements:com.apple.developer.team-identifier OTHERTEAM' "$profile"
export FIXTURE_HOST_PROFILE="$host_profile" FIXTURE_ACTIVITY_PROFILE="$profile"
: > "$FIXTURE_OP_CALLS"
deny 'profile validation precedes private certificate reads' bash "$bundle_root/ios/distribution/bundle.sh"
printf '%s\n' 'op://tuist/Atlas App Ad Hoc/Atlas_App_Ad_Hoc.mobileprovision' \
    'op://tuist/Atlas Live Activity Ad Hoc/Atlas_Live_Activity_Ad_Hoc.mobileprovision' > "$work/expected-op.log"
diff -u "$work/expected-op.log" "$FIXTURE_OP_CALLS"
pass 'invalid extension profile never retrieves private signing material'

fixture_bundle
validate_share_bundle "$app"
pass 'Share bundle identity and principal class'
"$plist" -c 'Set :NSExtension:NSExtensionPointIdentifier com.apple.widgetkit-extension' "$share/Info.plist"
deny 'Share rejects wrong extension point' validate_share_bundle "$app"
fixture_bundle
fixture_profile
"$plist" -c 'Set :Entitlements:application-identifier U6LC622NKF.dev.tuist.atlas.share' "$profile"
validate_live_activity_profile "$profile" "$host_profile" "$identity" dev.tuist.atlas.share
prepare_live_activity_distribution "$app" "$profile" "$work/share-entitlements.plist" AtlasShare
configure_share_group "$profile" "$work/share-entitlements.plist"
[[ $(plutil -extract application-identifier raw "$work/share-entitlements.plist") = U6LC622NKF.dev.tuist.atlas.share ]]
[[ $("$plist" -c 'Print :com.apple.security.application-groups:0' "$work/share-entitlements.plist") = group.dev.tuist.atlas.share ]]
for key in aps-environment keychain-access-groups com.apple.developer.associated-domains; do
    if "$plist" -c "Print :$key" "$work/share-entitlements.plist" >/dev/null 2>&1; then fail "Share inherited $key"; fi
done
pass 'Share distribution identity and group without host credentials'
"$plist" -c 'Set :Entitlements:com.apple.security.application-groups:0 group.other' "$profile"
deny 'wrong Share group' configure_share_group "$profile" "$work/share-entitlements.plist"
"$plist" -c 'Delete :Entitlements:com.apple.security.application-groups' "$profile"
deny 'missing Share group' configure_share_group "$profile" "$work/share-entitlements.plist"
"$plist" -c 'Add :Entitlements:com.apple.security.application-groups string group.dev.tuist.atlas.share' "$profile"
deny 'scalar Share group' configure_share_group "$profile" "$work/share-entitlements.plist"

: > "$FIXTURE_CALLS"
sign_live_activity_distribution "$app" fixture-identity "$work/keychain" "$work/host-entitlements.plist" \
    "$entitlements" "$work/share-entitlements.plist"
{
    printf 'scan\t%s\t%s\t%s\n' "$app/Atlas" "$activity/AtlasLiveActivity" "$share/AtlasShare"
    printf 'sign\t%s\t%s\n' "$activity" "$entitlements"
    printf 'verify\t%s\t\n' "$activity"
    printf 'sign\t%s\t%s\n' "$share" "$work/share-entitlements.plist"
    printf 'verify\t%s\t\n' "$share"
    printf 'sign\t%s\t%s\n' "$app" "$work/host-entitlements.plist"
    printf 'verify\t%s\t\n' "$app"
} > "$work/expected-signing.log"
diff -u "$work/expected-signing.log" "$FIXTURE_CALLS"
pass 'all executables scanned and both extensions signed before host'

fixture_profile
"$plist" -c 'Add :Entitlements:com.apple.security.application-groups:1 string group.unrelated' "$profile"
plutil -extract Entitlements xml1 -o "$work/host-entitlements.plist" "$profile"
configure_share_group "$profile" "$work/host-entitlements.plist"
[[ $("$plist" -c 'Print :com.apple.security.application-groups:0' "$work/host-entitlements.plist") = group.dev.tuist.atlas.share ]]
if "$plist" -c 'Print :com.apple.security.application-groups:1' "$work/host-entitlements.plist" >/dev/null 2>&1; then
    fail 'Unrelated App Group was retained'
fi
pass 'host group authorization narrows the exact dotted entitlement key'

isolated_share="$bundle_root/.once/out/AtlasIOSDevice/Atlas.app/PlugIns/AtlasShare.appex"
"$plist" -c 'Set :CFBundleIdentifier wrong' "$isolated_share/Info.plist"
: > "$FIXTURE_OP_CALLS"
deny 'Share bundle validation precedes all credential reads' bash "$bundle_root/ios/distribution/bundle.sh"
[[ ! -s "$FIXTURE_OP_CALLS" ]] || fail 'Read credentials before Share bundle validation'
"$plist" -c 'Set :CFBundleIdentifier dev.tuist.atlas.share' "$isolated_share/Info.plist"

fixture_profile
cp "$profile" "$work/share-profile.plist"
"$plist" -c 'Set :Entitlements:application-identifier U6LC622NKF.dev.tuist.atlas.share' \
    -c 'Set :Entitlements:com.apple.security.application-groups:0 group.other' "$work/share-profile.plist"
export FIXTURE_SHARE_PROFILE="$work/share-profile.plist"
: > "$FIXTURE_OP_CALLS"
deny 'Share group validation precedes private certificate reads' bash "$bundle_root/ios/distribution/bundle.sh"
printf '%s\n' 'op://tuist/Atlas App Ad Hoc/Atlas_App_Ad_Hoc.mobileprovision' \
    'op://tuist/Atlas Live Activity Ad Hoc/Atlas_Live_Activity_Ad_Hoc.mobileprovision' \
    'op://tuist/Atlas Share Ad Hoc/Atlas_Share_Ad_Hoc.mobileprovision' > "$work/expected-op.log"
diff -u "$work/expected-op.log" "$FIXTURE_OP_CALLS"
pass 'invalid Share profile never retrieves private signing material'

echo "All $passed extension packaging fixtures passed."
