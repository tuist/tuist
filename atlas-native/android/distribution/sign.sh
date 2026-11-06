#!/usr/bin/env bash
# Only protected publication reads distribution credentials. PR APKs remain debug-signed.
set -euo pipefail
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
: "${ATLAS_ANDROID_KEYSTORE_REF:?Configure the 1Password distribution keystore reference}"
: "${ATLAS_ANDROID_KEYSTORE_PASSWORD_REF:?Configure the 1Password keystore password reference}"
: "${ATLAS_ANDROID_KEY_ALIAS:?Configure the stable distribution key alias}"
: "${ATLAS_ANDROID_APP_LINK_SHA256:?Configure the same trusted SHA-256 fingerprints as the Atlas server}"
[[ $# -eq 2 ]] || { echo 'usage: sign.sh INPUT.apk OUTPUT.apk' >&2; exit 1; }
input="$1" output="$2"
if [[ "$ATLAS_ANDROID_APP_LINK_SHA256" == *$'\n'* || "$ATLAS_ANDROID_APP_LINK_SHA256" =~ ,[[:space:]]*$ ]]; then
    echo 'Use a single-line comma-separated list of complete Android SHA-256 fingerprints' >&2
    exit 1
fi
IFS=',' read -r -a fingerprints <<< "$ATLAS_ANDROID_APP_LINK_SHA256"
for candidate in "${fingerprints[@]}"; do
    candidate="${candidate#"${candidate%%[![:space:]]*}"}"
    candidate="${candidate%"${candidate##*[![:space:]]}"}"
    [[ "$candidate" =~ ^([0-9A-F]{2}:){31}[0-9A-F]{2}$ ]] || { echo 'Invalid trusted Android SHA-256 fingerprint: use uppercase colon-separated bytes' >&2; exit 1; }
done
signer="$ANDROID_HOME/build-tools/35.0.0/apksigner"
[[ -x "$signer" && -f "$input" ]] || { echo 'APK or Android build-tools 35.0.0 missing' >&2; exit 1; }
umask 077
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
op read "$ATLAS_ANDROID_KEYSTORE_REF" --out-file "$tmp/distribution.p12"
op read "$ATLAS_ANDROID_KEYSTORE_PASSWORD_REF" --out-file "$tmp/password"
# apksigner consumes password files as streams; the two reads need separate files.
cp "$tmp/password" "$tmp/key-password"
"$signer" sign --ks "$tmp/distribution.p12" --ks-key-alias "$ATLAS_ANDROID_KEY_ALIAS" \
    --ks-pass "file:$tmp/password" --key-pass "file:$tmp/key-password" --out "$tmp/Atlas.apk" "$input"
"$signer" verify --verbose --print-certs "$tmp/Atlas.apk" > "$tmp/signature"
# Public certificate digests are not credentials; reject mismatched server trust before publication.
fingerprint=$(awk '/^Signer #1 certificate SHA-256 digest:/ {print toupper($NF)}' "$tmp/signature")
[[ "$fingerprint" =~ ^[0-9A-F]{64}$ ]] || { echo 'Cannot read the signed APK certificate digest' >&2; exit 1; }
if grep -F 'CN=Android Debug' "$tmp/signature" >/dev/null; then
    echo 'Distribution must not trust an Android debug certificate' >&2
    exit 1
fi
trusted=false
for candidate in "${fingerprints[@]}"; do
    candidate=$(printf '%s' "$candidate" | tr -d ':[:space:]')
    if [[ "$candidate" == "$fingerprint" ]]; then trusted=true; fi
done
[[ "$trusted" == true ]] || { echo 'The distribution key does not match the configured Atlas App Links fingerprints' >&2; exit 1; }
mkdir -p "$(dirname "$output")"
cp "$tmp/Atlas.apk" "$output"
echo "Signed Atlas APK with trusted certificate SHA-256 $fingerprint"
