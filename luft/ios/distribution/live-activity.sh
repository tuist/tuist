#!/usr/bin/env bash
# Validates, provisions and signs the embedded Live Activity extension for ad-hoc
# device previews. Adapted from atlas-native/ios/distribution/live-activity.sh.

live_activity_id=dev.tuist.code.live-activity
live_activity_product=LuftLiveActivity

live_activity_plist() {
    /usr/libexec/PlistBuddy "$@"
}

# Checks the built app before any credential is read.
validate_live_activity_bundle() {
    local app="$1" activity="$1/PlugIns/$live_activity_product.appex" other
    if [[ ! -d "$activity" || -L "$activity" || -L "$app/PlugIns" || ! -x "$activity/$live_activity_product" ]]; then
        echo "Build and embed $live_activity_product.appex before signing the device app" >&2
        return 1
    fi
    [[ $(live_activity_plist -c 'Print :CFBundleIdentifier' "$activity/Info.plist") = "$live_activity_id" ]] || return 1
    [[ $(live_activity_plist -c 'Print :CFBundleExecutable' "$activity/Info.plist") = "$live_activity_product" ]] || return 1
    [[ $(live_activity_plist -c 'Print :CFBundlePackageType' "$activity/Info.plist") = 'XPC!' ]] || return 1
    [[ $(live_activity_plist -c 'Print :NSExtension:NSExtensionPointIdentifier' "$activity/Info.plist") = com.apple.widgetkit-extension ]] || return 1
    xcrun vtool -show-build "$activity/$live_activity_product" | grep -Eq 'platform IOS$' || {
        echo "Expected an iOS device Live Activity executable, not a simulator build" >&2
        return 1
    }
    for other in "$app"/PlugIns/*; do
        if [[ "$other" != "$activity" && ( -e "$other" || -L "$other" ) ]]; then
            echo "Unexpected extension in the distribution app: $other" >&2
            return 1
        fi
    done
}

# Checks the extension's own ad-hoc profile against the host's: same team, unexpired,
# every host device and the host's signing certificate.
validate_live_activity_profile() {
    local profile="$1" host_profile="$2" identity="$3"
    local expires expiration device candidate index=0 other_index found encoded fingerprint
    [[ $(live_activity_plist -c 'Print :Entitlements:application-identifier' "$profile") = "U6LC622NKF.$live_activity_id" ]] || {
        echo "Expected the $live_activity_id provisioning profile" >&2
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
        echo "The Luft Live Activity provisioning profile has expired" >&2
        return 1
    }
    live_activity_plist -c 'Print :ProvisionedDevices:0' "$profile" >/dev/null 2>&1 || {
        echo "The Live Activity profile must include registered devices" >&2
        return 1
    }
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
            echo "The Live Activity profile must authorize every device in the Tuist Code Ad Hoc profile" >&2
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

# Embeds the profile, matches the host's versions and writes identity-only
# entitlements: the extension never inherits the host's APNs or Keychain access.
prepare_live_activity_distribution() {
    local app="$1" profile="$2" entitlements="$3" version
    local activity="$app/PlugIns/$live_activity_product.appex"
    cp "$profile" "$activity/embedded.mobileprovision" || return 1
    for version in CFBundleVersion CFBundleShortVersionString; do
        live_activity_plist -c "Set :$version $(live_activity_plist -c "Print :$version" "$app/Info.plist")" "$activity/Info.plist" || return 1
    done
    cat > "$entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>U6LC622NKF.$live_activity_id</string>
<key>com.apple.developer.team-identifier</key><string>U6LC622NKF</string>
<key>get-task-allow</key><false/>
</dict></plist>
PLIST
}

# Signs inside-out: the extension with its own entitlements, then the host.
# --deep only verifies; it is never a signing shortcut.
sign_live_activity_distribution() {
    local app="$1" identity="$2" keychain="$3" host_entitlements="$4" activity_entitlements="$5"
    local activity="$app/PlugIns/$live_activity_product.appex"
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none \
        --generate-entitlement-der --entitlements "$activity_entitlements" "$activity" || return 1
    codesign --verify --strict "$activity" || return 1
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none \
        --entitlements "$host_entitlements" "$app" || return 1
    codesign --verify --strict --deep "$app"
}
