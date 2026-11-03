#!/usr/bin/env bash

# These guards consume a plist decoded by `security cms -D`, never an unsigned
# profile supplied in place of Apple's CMS envelope in the distribution path.
macos_profile_value() {
    plutil -extract "$2" raw -expect "$3" -o - "$1"
}

macos_push_certificate_ids() (
    set -euo pipefail
    local profile=$1 count index encoded subject details starts ends now found=false
    count=$(macos_profile_value "$profile" DeveloperCertificates array)
    [[ "$count" -gt 0 && "$count" -le 32 ]] || return 1
    now=$(date +%s)
    for ((index = 0; index < count; index++)); do
        encoded=$(macos_profile_value "$profile" "DeveloperCertificates.$index" data)
        subject=$(printf '%s' "$encoded" | base64 -D | openssl x509 -inform DER -noout -subject -nameopt RFC2253)
        subject=${subject#subject=}
        subject=${subject# }
        [[ ",$subject," = *',OU=U6LC622NKF,'* && ",$subject," = *',CN=Developer ID Application: Tuist GmbH (U6LC622NKF),'* ]] || continue
        details=$(printf '%s' "$encoded" | base64 -D | openssl x509 -inform DER -noout -text)
        grep -F '1.2.840.113635.100.6.1.13:' <<< "$details" >/dev/null || continue
        starts=$(printf '%s' "$encoded" | base64 -D | openssl x509 -inform DER -noout -startdate)
        ends=$(printf '%s' "$encoded" | base64 -D | openssl x509 -inform DER -noout -enddate)
        starts=$(LC_ALL=C date -j -u -f '%b %e %T %Y %Z' "${starts#notBefore=}" +%s)
        ends=$(LC_ALL=C date -j -u -f '%b %e %T %Y %Z' "${ends#notAfter=}" +%s)
        [[ "$starts" -le "$now" && "$ends" -gt "$now" ]] || continue
        printf '%s' "$encoded" | base64 -D | shasum -a 1 | awk '{ print toupper($1) }'
        found=true
    done
    [[ "$found" = true ]] || { echo 'Profile has no current Tuist Developer ID Application certificate' >&2; return 1; }
)

validate_macos_push_profile() (
    set -euo pipefail
    local profile=$1 prefix application team environment created expires now key
    [[ $(macos_profile_value "$profile" Platform array) = 1 && $(macos_profile_value "$profile" Platform.0 string) = OSX ]] || {
        echo 'Expected a Mac Developer ID profile (Platform OSX)' >&2; return 1;
    }
    [[ $(macos_profile_value "$profile" ProvisionsAllDevices bool) = true ]] || {
        echo 'Use a Developer ID profile, not development or Mac App Store provisioning' >&2; return 1;
    }
    if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$profile" >/dev/null 2>&1; then
        echo 'Developer ID provisioning must not restrict registered devices' >&2; return 1
    fi
    [[ $(macos_profile_value "$profile" TeamIdentifier array) = 1 && $(macos_profile_value "$profile" TeamIdentifier.0 string) = U6LC622NKF ]] || return 1
    [[ $(macos_profile_value "$profile" ApplicationIdentifierPrefix array) = 1 ]] || return 1
    prefix=$(macos_profile_value "$profile" ApplicationIdentifierPrefix.0 string)
    [[ "$prefix" =~ ^[A-Z0-9]{10}$ ]] || return 1
    application=$(macos_profile_value "$profile" 'Entitlements.com\.apple\.application-identifier' string)
    team=$(macos_profile_value "$profile" 'Entitlements.com\.apple\.developer\.team-identifier' string)
    environment=$(macos_profile_value "$profile" 'Entitlements.com\.apple\.developer\.aps-environment' string)
    [[ "$application" = "$prefix.dev.tuist.atlas" && "$team" = U6LC622NKF && "$environment" = production ]] || {
        echo 'Profile must authorize dev.tuist.atlas and production macOS APNs for Tuist' >&2; return 1;
    }
    for key in 'com\.apple\.security\.get-task-allow' get-task-allow; do
        if plutil -type "Entitlements.$key" "$profile" >/dev/null 2>&1; then
            [[ $(macos_profile_value "$profile" "Entitlements.$key" bool) = false ]] || return 1
        fi
    done
    created=$(macos_profile_value "$profile" CreationDate date)
    expires=$(macos_profile_value "$profile" ExpirationDate date)
    created=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$created" +%s)
    expires=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s)
    now=$(date +%s)
    [[ "$created" -le "$now" && "$expires" -gt "$now" && "$expires" -gt "$created" ]] || {
        echo 'The Atlas macOS profile is expired or not yet valid' >&2; return 1;
    }
    macos_push_certificate_ids "$profile" >/dev/null
)

macos_push_signing_identity() (
    set -euo pipefail
    local profile=$1 keychain=$2 ids identities fingerprint
    ids=$(macos_push_certificate_ids "$profile")
    identities=$(security find-identity -v -p codesigning "$keychain")
    while IFS= read -r fingerprint; do
        if awk -v fingerprint="$fingerprint" '$2 == fingerprint { found=1 } END { exit !found }' <<< "$identities"; then
            printf '%s\n' "$fingerprint"
            return 0
        fi
    done <<< "$ids"
    echo 'No valid private signing identity matches the Atlas macOS profile certificates' >&2
    return 1
)

write_macos_push_entitlements() (
    set -euo pipefail
    local profile=$1 output=$2 base=$3 key value
    validate_macos_push_profile "$profile"
    cp "$base" "$output"
    for key in com.apple.application-identifier com.apple.developer.team-identifier com.apple.developer.aps-environment; do
        value=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:$key" "$profile")
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$output"
    done
)

verify_macos_push_signature() (
    set -euo pipefail
    local app=$1 identity=$2 requested=$3 work=$4 actual key value team
    codesign --display --extract-certificates="$work/signed-" "$app"
    actual=$(shasum -a 1 "$work/signed-0" | awk '{print toupper($1)}')
    [[ "$actual" = "$identity" ]] || { echo 'Actual signing certificate differs from the authorized profile identity' >&2; return 1; }
    team=$(codesign --display --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [[ "$team" = U6LC622NKF ]] || return 1
    codesign --display --entitlements - --xml "$app" > "$work/signed-entitlements.plist"
    [[ $(/usr/bin/xmllint --xpath 'count(/plist/dict/key)' "$work/signed-entitlements.plist") = 4 ]] || return 1
    for key in com.apple.application-identifier com.apple.developer.team-identifier com.apple.developer.aps-environment com.apple.security.device.audio-input; do
        value=$(/usr/libexec/PlistBuddy -c "Print :$key" "$requested")
        [[ $(/usr/libexec/PlistBuddy -c "Print :$key" "$work/signed-entitlements.plist") = "$value" ]] || return 1
    done
)
