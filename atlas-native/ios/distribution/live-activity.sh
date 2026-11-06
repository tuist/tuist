#!/usr/bin/env bash

live_activity_plist() {
    /usr/libexec/PlistBuddy "$@"
}

validate_live_activity_bundle() {
    local app="$1" activity="$1/PlugIns/AtlasLiveActivity.appex" other
    if [[ ! -d "$activity" || -L "$activity" || -L "$app/PlugIns" || ! -x "$activity/AtlasLiveActivity" ]]; then
        echo "Build and embed AtlasLiveActivity.appex before signing the device app" >&2
        return 1
    fi
    [[ $(live_activity_plist -c 'Print :CFBundleIdentifier' "$activity/Info.plist") = dev.tuist.atlas.live-activity ]] || return 1
    [[ $(live_activity_plist -c 'Print :CFBundleExecutable' "$activity/Info.plist") = AtlasLiveActivity ]] || return 1
    [[ $(live_activity_plist -c 'Print :CFBundlePackageType' "$activity/Info.plist") = 'XPC!' ]] || return 1
    [[ $(live_activity_plist -c 'Print :NSExtension:NSExtensionPointIdentifier' "$activity/Info.plist") = com.apple.widgetkit-extension ]] || return 1
    xcrun vtool -show-build "$activity/AtlasLiveActivity" | grep -Eq 'platform IOS$' || {
        echo "Expected an iOS device Live Activity executable, not a simulator build" >&2
        return 1
    }
    for other in "$app"/PlugIns/*.appex; do
        if [[ "$other" != "$activity" && "$other" != "$app/PlugIns/AtlasShare.appex" && ( -e "$other" || -L "$other" ) ]]; then
            echo "Unexpected extension in the distribution app: $other" >&2
            return 1
        fi
    done
}

validate_live_activity_profile() {
    local profile="$1" host_profile="$2" identity="$3" expires expiration
    local bundle_id=${4:-dev.tuist.atlas.live-activity}
    local devices device candidate index=0 other_index found encoded fingerprint
    [[ $(live_activity_plist -c 'Print :Entitlements:application-identifier' "$profile") = "U6LC622NKF.$bundle_id" ]] || {
        echo "Expected the $bundle_id provisioning profile" >&2
        return 1
    }
    [[ $(live_activity_plist -c 'Print :Entitlements:com.apple.developer.team-identifier' "$profile") = U6LC622NKF ]] || {
        echo "Expected the Tuist signing team for the Live Activity" >&2
        return 1
    }
    [[ $(live_activity_plist -c 'Print :Entitlements:get-task-allow' "$profile") = false ]] || {
        echo "The Live Activity requires an ad-hoc profile, not a development profile" >&2
        return 1
    }
    candidate=$(live_activity_plist -c 'Print :ProvisionsAllDevices' "$profile" 2>/dev/null) || candidate=false
    [[ "$candidate" = false ]] || {
        echo "Use a registered-device ad-hoc Live Activity profile, not enterprise distribution" >&2
        return 1
    }
    expires=$(plutil -extract ExpirationDate raw "$profile") || return 1
    expiration=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s) || return 1
    [[ "$expiration" -gt $(date +%s) ]] || {
        echo "The Atlas Live Activity provisioning profile has expired" >&2
        return 1
    }
    devices=$(live_activity_plist -c 'Print :ProvisionedDevices' "$profile") || return 1
    [[ "$devices" = 'Array {'* ]] || return 1
    live_activity_plist -c 'Print :ProvisionedDevices:0' "$profile" >/dev/null || {
        echo "The Live Activity profile must include registered devices" >&2
        return 1
    }
    live_activity_plist -c 'Print :ProvisionedDevices:0' "$host_profile" >/dev/null || return 1
    while device=$(live_activity_plist -c "Print :ProvisionedDevices:$index" "$host_profile" 2>/dev/null); do
        [[ "$device" =~ ^[[:alnum:]-]+$ ]] || return 1
        other_index=0
        found=false
        while candidate=$(live_activity_plist -c "Print :ProvisionedDevices:$other_index" "$profile" 2>/dev/null); do
            [[ "$candidate" =~ ^[[:alnum:]-]+$ ]] || return 1
            if [[ "$candidate" = "$device" ]]; then found=true; fi
            other_index=$((other_index + 1))
        done
        [[ "$found" = true ]] || {
            echo "The Live Activity profile must authorize every device in the Atlas app profile" >&2
            return 1
        }
        index=$((index + 1))
    done
    index=0
    while encoded=$(plutil -extract "DeveloperCertificates.$index" raw "$profile" 2>/dev/null); do
        fingerprint=$(printf '%s' "$encoded" | base64 -D | shasum -a 1 | awk '{print toupper($1)}') || return 1
        if [[ "$fingerprint" = "$identity" ]]; then return 0; fi
        index=$((index + 1))
    done
    echo "The Live Activity profile does not authorize the app's signing certificate" >&2
    return 1
}

prepare_live_activity_distribution() {
    local app="$1" profile="$2" entitlements="$3" product=${4:-AtlasLiveActivity} version
    local activity="$app/PlugIns/$product.appex"
    cp "$profile" "$activity/embedded.mobileprovision" || return 1
    for version in CFBundleVersion CFBundleShortVersionString; do
        live_activity_plist -c "Set :$version $(live_activity_plist -c "Print :$version" "$app/Info.plist")" "$activity/Info.plist" || return 1
    done
    # Request only the identity entitlements validated against this extension's
    # profile. It never inherits the host's APNs, domain or Keychain permissions.
    cat > "$entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>U6LC622NKF.dev.tuist.atlas.live-activity</string>
<key>com.apple.developer.team-identifier</key><string>U6LC622NKF</string>
<key>get-task-allow</key><false/>
</dict></plist>
PLIST
    if [[ "$product" = AtlasShare ]]; then
        live_activity_plist -c 'Set :application-identifier U6LC622NKF.dev.tuist.atlas.share' "$entitlements" || return 1
    fi
}

sign_live_activity_distribution() {
    local app="$1" identity="$2" keychain="$3" host_entitlements="$4" activity_entitlements="$5"
    local share_entitlements=${6:-} share="$1/PlugIns/AtlasShare.appex"
    local activity="$1/PlugIns/AtlasLiveActivity.appex" library framework
    local framework_dirs=("$app/Frameworks")
    local scans=(--scan-executable "$app/Atlas" --scan-executable "$activity/AtlasLiveActivity")
    if [[ -n "$share_entitlements" ]]; then
        scans+=(--scan-executable "$share/AtlasShare")
        if [[ -d "$share/Frameworks" ]]; then framework_dirs+=("$share/Frameworks"); fi
    fi
    mkdir -p "$app/Frameworks" || return 1
    xcrun swift-stdlib-tool --copy "${scans[@]}" --platform iphoneos --destination "$app/Frameworks" || return 1
    if [[ -d "$activity/Frameworks" ]]; then framework_dirs+=("$activity/Frameworks"); fi
    while IFS= read -r -d '' library; do
        codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$library" || return 1
    done < <(find "${framework_dirs[@]}" -type f -name '*.dylib' -print0)
    while IFS= read -r -d '' framework; do
        codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$framework" || return 1
    done < <(find "${framework_dirs[@]}" -depth -type d -name '*.framework' -print0)
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none \
        --generate-entitlement-der --entitlements "$activity_entitlements" "$activity" || return 1
    codesign --verify --deep --strict "$activity" || return 1
    if [[ -n "$share_entitlements" ]]; then
        codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none \
            --generate-entitlement-der --entitlements "$share_entitlements" "$share" || return 1
        codesign --verify --deep --strict "$share" || return 1
    fi
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none \
        --generate-entitlement-der --entitlements "$host_entitlements" "$app" || return 1
    codesign --verify --deep --strict "$app"
}
