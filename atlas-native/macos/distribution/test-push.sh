#!/usr/bin/env bash
set -euo pipefail
umask 077

scripts=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=push.sh
source "$scripts/push.sh"
[[ $# = 0 || ( $# = 2 && $1 = --fixture ) ]] || { echo 'Usage: test-push.sh [--fixture <new directory>]' >&2; exit 2; }
if [[ $# = 2 ]]; then
    work=$2
    [[ ! -e "$work" ]] || exit 1
    mkdir -p "$work"
else
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
fi

cat > "$work/certificate.cnf" <<'CONF'
[req]
distinguished_name = subject
x509_extensions = developer_id
[subject]
[developer_id]
1.2.840.113635.100.6.1.13 = DER:05:00
CONF
for name in good other; do
    openssl req -new -x509 -newkey rsa:2048 -nodes -days 2 -sha256 \
        -subj '/CN=Developer ID Application: Tuist GmbH (U6LC622NKF)/OU=U6LC622NKF/O=Disposable fixture' \
        -config "$work/certificate.cnf" -keyout "$work/$name.key" -out "$work/$name.pem" > /dev/null 2>&1
    openssl x509 -in "$work/$name.pem" -outform DER -out "$work/$name.der"
    rm "$work/$name.key" "$work/$name.pem"
done
shasum -a 1 "$work/good.der" | awk '{ print toupper($1) }' > "$work/identity"
cat > "$work/profile.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Platform</key><array><string>OSX</string></array>
<key>ProvisionsAllDevices</key><true/>
<key>TeamIdentifier</key><array><string>U6LC622NKF</string></array>
<key>ApplicationIdentifierPrefix</key><array><string>LEGACY1234</string></array>
<key>CreationDate</key><date>$(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ)</date>
<key>ExpirationDate</key><date>$(date -u -v+1d +%Y-%m-%dT%H:%M:%SZ)</date>
<key>DeveloperCertificates</key><array><data>$(base64 < "$work/good.der")</data></array>
<key>Entitlements</key><dict>
<key>com.apple.application-identifier</key><string>LEGACY1234.dev.tuist.atlas</string>
<key>com.apple.developer.team-identifier</key><string>U6LC622NKF</string>
<key>com.apple.developer.aps-environment</key><string>production</string>
<key>com.apple.security.get-task-allow</key><false/>
</dict></dict></plist>
PLIST
validate_macos_push_profile "$work/profile.plist"
if [[ $# = 2 ]]; then exit 0; fi

write_macos_push_entitlements "$work/profile.plist" "$work/entitlements.plist" "$scripts/entitlements.plist"
buddy=/usr/libexec/PlistBuddy
[[ $("$buddy" -c 'Print :com.apple.application-identifier' "$work/entitlements.plist") = LEGACY1234.dev.tuist.atlas ]]
[[ $("$buddy" -c 'Print :com.apple.developer.aps-environment' "$work/entitlements.plist") = production ]]
[[ $("$buddy" -c 'Print :com.apple.security.device.audio-input' "$work/entitlements.plist") = true ]]
[[ $(/usr/bin/xmllint --xpath 'count(/plist/dict/key)' "$work/entitlements.plist") = 4 ]]

for mutation in \
    'Set :Platform:0 iOS' \
    'Set :ProvisionsAllDevices false' \
    'Add :ProvisionedDevices array' \
    'Set :TeamIdentifier:0 XXXXXXXXXX' \
    'Set :Entitlements:com.apple.application-identifier LEGACY1234.dev.tuist.atlas.macos' \
    'Set :Entitlements:com.apple.developer.team-identifier XXXXXXXXXX' \
    'Set :Entitlements:com.apple.developer.aps-environment development' \
    'Delete :Entitlements:com.apple.developer.aps-environment' \
    'Set :Entitlements:com.apple.security.get-task-allow true' \
    ExpirationDate \
    CreationDate \
    'Delete :DeveloperCertificates:0'; do
    cp "$work/profile.plist" "$work/rejected.plist"
    case "$mutation" in
        ExpirationDate) plutil -replace ExpirationDate -date 2000-01-01T00:00:00Z "$work/rejected.plist" ;;
        CreationDate) plutil -replace CreationDate -date 2099-01-01T00:00:00Z "$work/rejected.plist" ;;
        *) "$buddy" -c "$mutation" "$work/rejected.plist" ;;
    esac
    if validate_macos_push_profile "$work/rejected.plist" > "$work/rejection.log" 2>&1; then
        echo "Incorrectly accepted profile: $mutation" >&2; exit 1
    fi
done
echo 'macOS push profile fixtures passed (legacy prefix, least-privilege entitlements and 12 rejected profiles)'
