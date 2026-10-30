#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
source "$root/associated-domains.sh"
plist=/usr/libexec/PlistBuddy
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
key=com.apple.developer.associated-domains
domain=applinks:atlas.tuist.dev
profile="$work/profile.plist"
entitlements="$work/entitlements.plist"

fixture() {
    cat > "$profile" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Entitlements</key><dict/></dict></plist>
PLIST
    case "$1" in
        scalar-wildcard) "$plist" -c "Add :Entitlements:$key string *" "$profile" ;;
        scalar-exact) "$plist" -c "Add :Entitlements:$key string $domain" "$profile" ;;
        array-wildcard|array-exact|empty-array|nested-array|wrong-domain-array|wrong-service-array)
            "$plist" -c "Add :Entitlements:$key array" "$profile"
            case "$1" in
                array-wildcard) "$plist" -c "Add :Entitlements:$key:0 string *" "$profile" ;;
                array-exact)
                    "$plist" -c "Add :Entitlements:$key:0 string applinks:other.example.org" \
                        -c "Add :Entitlements:$key:1 string $domain" "$profile" ;;
                nested-array) "$plist" -c "Add :Entitlements:$key:0 array" -c "Add :Entitlements:$key:0:0 string *" "$profile" ;;
                wrong-domain-array) "$plist" -c "Add :Entitlements:$key:0 string applinks:other.example.org" "$profile" ;;
                wrong-service-array) "$plist" -c "Add :Entitlements:$key:0 string webcredentials:atlas.tuist.dev" "$profile" ;;
            esac ;;
        missing) ;;
        empty-string) "$plist" -c "Add :Entitlements:$key string" "$profile" ;;
        wrong-domain-string) "$plist" -c "Add :Entitlements:$key string applinks:other.example.org" "$profile" ;;
        wrong-service-string) "$plist" -c "Add :Entitlements:$key string webcredentials:atlas.tuist.dev" "$profile" ;;
        wrong-wildcard) "$plist" -c "Add :Entitlements:$key string **" "$profile" ;;
        wrong-bool) "$plist" -c "Add :Entitlements:$key bool true" "$profile" ;;
        wrong-integer) "$plist" -c "Add :Entitlements:$key integer 1" "$profile" ;;
        wrong-dict) "$plist" -c "Add :Entitlements:$key dict" -c "Add :Entitlements:$key:0 string *" "$profile" ;;
        *) echo "Unknown fixture: $1" >&2; exit 1 ;;
    esac
    plutil -extract Entitlements xml1 -o "$entitlements" "$profile"
}

for name in scalar-wildcard scalar-exact array-wildcard array-exact; do
    fixture "$name"
    configure_associated_domains "$profile" "$entitlements"
    [[ $("$plist" -c "Print :$key:0" "$entitlements") == "$domain" ]]
    if "$plist" -c "Print :$key:1" "$entitlements" >/dev/null 2>&1; then
        echo "$name requested more than the hosted domain" >&2
        exit 1
    fi
    echo "Passed $name"
done

for name in missing empty-array empty-string wrong-domain-string wrong-service-string wrong-wildcard \
    wrong-bool wrong-integer wrong-dict nested-array wrong-domain-array wrong-service-array; do
    fixture "$name"
    cp "$entitlements" "$work/before.plist"
    if configure_associated_domains "$profile" "$entitlements" 2> "$work/error.log"; then
        echo "$name incorrectly authorized Associated Domains" >&2
        exit 1
    fi
    cmp -s "$entitlements" "$work/before.plist"
    grep -q 'regenerate the Atlas ad-hoc provisioning profile' "$work/error.log"
    echo "Passed $name (denied without changing entitlements)"
done

echo 'All 16 Associated Domains provisioning fixtures passed.'
