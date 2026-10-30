#!/usr/bin/env bash

# The profile authorizes capabilities; the app signature requests only our domain.
configure_associated_domains() {
    local profile="$1" entitlements="$2" domain="applinks:atlas.tuist.dev"
    local allowed=false value index=0
    value=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.associated-domains' "$profile" 2>/dev/null) || value=''
    if [[ "$value" == '*' || "$value" == "$domain" ]]; then
        allowed=true
    elif [[ "$value" == 'Array {'* ]]; then
        while value=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.associated-domains:$index" "$profile" 2>/dev/null); do
            if [[ "$value" == '*' || "$value" == "$domain" ]]; then allowed=true; fi
            index=$((index + 1))
        done
    fi
    if [[ "$allowed" != true ]]; then
        echo 'Enable Associated Domains for dev.tuist.atlas and regenerate the Atlas ad-hoc provisioning profile before publishing.' >&2
        return 1
    fi
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.developer.associated-domains' \
        -c 'Add :com.apple.developer.associated-domains array' \
        -c "Add :com.apple.developer.associated-domains:0 string $domain" "$entitlements"
}
