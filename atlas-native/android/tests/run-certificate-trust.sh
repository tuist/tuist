#!/usr/bin/env bash
set -euo pipefail
umask 077

# Explicitly scoped to an owned emulator and a separately signed test APK.
if [[ $# -ne 3 || ${ATLAS_TRUST_LIVE:-} != 1 ]]; then
  echo "Usage: ATLAS_TRUST_LIVE=1 ANDROID_HOME=... JAVA_HOME=... $0 ATLAS_DEBUG_APK EMULATOR_SERIAL ANDROID_DEBUG_KEYSTORE" >&2
  exit 2
fi
: "${ANDROID_HOME:?Set ANDROID_HOME}"
: "${JAVA_HOME:?Set JAVA_HOME}"
apk=$1
serial=$2
keystore=$3
sdk="$ANDROID_HOME/platforms/android-35/android.jar"
tools="$ANDROID_HOME/build-tools/${ANDROID_BUILD_TOOLS_VERSION:-35.0.0}"
adb="$ANDROID_HOME/platform-tools/adb"
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
[[ $serial == emulator-* ]] || { echo "Refusing a non-emulator target" >&2; exit 2; }
[[ $("$adb" -s "$serial" shell getprop ro.kernel.qemu | tr -d '\r') == 1 ]] || { echo "Target is not an emulator" >&2; exit 2; }
"$adb" -s "$serial" emu avd name
[[ -z $("$adb" -s "$serial" shell pm path dev.tuist.atlas.trusttest) ]] || { echo "Test package already exists; use an idle owned emulator" >&2; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/atlas-certificate-trust.XXXXXX")
installed=0
cleanup() {
  if [[ $installed == 1 ]]; then "$adb" -s "$serial" uninstall dev.tuist.atlas.trusttest >/dev/null 2>&1 || true; fi
  rm -rf -- "$work"
}
trap cleanup EXIT

# Public certificate metadata only. Never sign with a production identity or re-sign the target APK.
"$tools/apksigner" verify --print-certs "$apk" > "$work/target-signer.txt"
"$tools/aapt2" dump badging "$apk" > "$work/target-package.txt"
grep -q "^package: name='dev.tuist.atlas' " "$work/target-package.txt" || { echo "Target is not Atlas" >&2; exit 2; }
grep -q 'certificate DN: .*CN=Android Debug' "$work/target-signer.txt" || { echo "Target is not an Android debug build" >&2; exit 2; }
"$JAVA_HOME/bin/keytool" -exportcert -keystore "$keystore" -alias androiddebugkey -storepass android -file "$work/debug.der" >/dev/null 2>&1
expected=$(openssl dgst -sha256 "$work/debug.der" | awk '{print tolower($NF)}')
actual=$(awk '/Signer #1 certificate SHA-256 digest:/ {print tolower($NF)}' "$work/target-signer.txt")
[[ $actual == "$expected" ]] || { echo "Debug signer does not match target APK" >&2; exit 2; }

mkdir -p "$work/classes" "$work/dex"
"$JAVA_HOME/bin/javac" --release 8 -classpath "$sdk" -d "$work/classes" "$source_dir/CertificateTrustInstrumentation.java"
"$JAVA_HOME/bin/jar" cf "$work/classes.jar" -C "$work/classes" .
JAVA_HOME="$JAVA_HOME" "$tools/d8" --min-api 26 --lib "$sdk" --output "$work/dex" "$work/classes.jar"
printf '%s\n' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.tuist.atlas.trusttest"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><uses-permission android:name="android.permission.INTERNET"/><application android:label="Atlas certificate controls"/><instrumentation android:name="dev.tuist.atlas.trusttest.CertificateTrustInstrumentation" android:targetPackage="dev.tuist.atlas"/></manifest>' > "$work/AndroidManifest.xml"
"$tools/aapt2" link -o "$work/test-unsigned.apk" -I "$sdk" --manifest "$work/AndroidManifest.xml"
(cd "$work/dex" && zip -q -j "$work/test-unsigned.apk" classes.dex)
"$tools/zipalign" -f 4 "$work/test-unsigned.apk" "$work/test-aligned.apk"
"$tools/apksigner" sign --ks "$keystore" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$work/test.apk" "$work/test-aligned.apk"
"$adb" -s "$serial" install -r "$apk"
"$adb" -s "$serial" install "$work/test.apk"
installed=1
"$adb" -s "$serial" shell am instrument -w -r dev.tuist.atlas.trusttest/dev.tuist.atlas.trusttest.CertificateTrustInstrumentation | tee "$work/result.txt"
grep -q 'PASS: actual Atlas APK/native NSC' "$work/result.txt"
grep -q 'INSTRUMENTATION_CODE: -1' "$work/result.txt"
