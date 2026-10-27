#!/usr/bin/env bash

validate_share_bundle() {
    local share="$1/PlugIns/AtlasShare.appex"
    [[ -d "$share" && ! -L "$share" && -x "$share/AtlasShare" ]] || {
        echo 'Build and embed AtlasShare.appex before signing' >&2
        return 1
    }
    [[ $(live_activity_plist -c 'Print :CFBundleIdentifier' "$share/Info.plist") = dev.tuist.atlas.share ]] || return 1
    [[ $(live_activity_plist -c 'Print :CFBundleExecutable' "$share/Info.plist") = AtlasShare ]] || return 1
    [[ $(live_activity_plist -c 'Print :CFBundlePackageType' "$share/Info.plist") = 'XPC!' ]] || return 1
    [[ $(live_activity_plist -c 'Print :NSExtension:NSExtensionPointIdentifier' "$share/Info.plist") = com.apple.share-services ]] || return 1
    [[ $(live_activity_plist -c 'Print :NSExtension:NSExtensionPrincipalClass' "$share/Info.plist") = ShareViewController ]] || return 1
    xcrun vtool -show-build "$share/AtlasShare" | grep -Eq 'platform IOS$'
}

configure_share_group() {
    local profile="$1" entitlements="$2" groups candidate index=0 found=false
    groups=$(live_activity_plist -c 'Print :Entitlements:com.apple.security.application-groups' "$profile") || return 1
    [[ "$groups" = 'Array {'* ]] || return 1
    while candidate=$(live_activity_plist -c "Print :Entitlements:com.apple.security.application-groups:$index" "$profile" 2>/dev/null); do
        if [[ "$candidate" = group.dev.tuist.atlas.share ]]; then found=true; fi
        index=$((index + 1))
    done
    [[ "$found" = true ]] || {
        echo 'Both Atlas and Share profiles must authorize group.dev.tuist.atlas.share' >&2
        return 1
    }
    live_activity_plist -c 'Delete :com.apple.security.application-groups' "$entitlements" >/dev/null 2>&1 || true
    live_activity_plist -c 'Add :com.apple.security.application-groups array' \
        -c 'Add :com.apple.security.application-groups:0 string group.dev.tuist.atlas.share' "$entitlements"
}
