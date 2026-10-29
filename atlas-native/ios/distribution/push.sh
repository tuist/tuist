#!/usr/bin/env bash

configure_push_notifications() {
    local profile="$1" entitlements="$2" plist=/usr/libexec/PlistBuddy environment
    environment=$("$plist" -c 'Print :Entitlements:aps-environment' "$profile" 2>/dev/null) || {
        echo "Enable Push Notifications for dev.tuist.atlas and regenerate the Atlas ad-hoc profile" >&2
        return 1
    }
    if [[ "$environment" != production ]]; then
        echo "Atlas ad-hoc distribution requires a production APNs entitlement" >&2
        return 1
    fi
    "$plist" -c 'Delete :aps-environment' "$entitlements" 2>/dev/null || true
    "$plist" -c 'Add :aps-environment string production' "$entitlements"
}
