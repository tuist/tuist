#!/bin/bash
# Release-pipeline-shaped probe: login keychain, codesign through a
# temporary keychain, create-dmg with Finder styling. Every command that
# could wait on a GUI prompt runs under a deadline so a prompt shows up as
# a TIMEOUT instead of a hung job.

set -uo pipefail

OUT="${RUNNER_TEMP}/diag"
WORK="${RUNNER_TEMP}/release-probe"
mkdir -p "${OUT}" "${WORK}"
RESULTS="${OUT}/results.txt"

deadline() {
  local seconds=$1
  shift
  perl -e 'alarm shift; exec @ARGV' "${seconds}" "$@"
}

record() {
  local name=$1 rc=$2 started=$3
  local elapsed=$(($(date +%s) - started))
  local verdict=PASS
  [ "${rc}" -eq 0 ] || verdict=FAIL
  [ "${rc}" -eq 142 ] && verdict=TIMEOUT
  echo "RESULT ${name} ${verdict} rc=${rc} ${elapsed}s" | tee -a "${RESULTS}"
}

step() {
  local name=$1 seconds=$2 started rc
  shift 2
  started=$(date +%s)
  echo "::group::${name}"
  deadline "${seconds}" "$@"
  rc=$?
  echo "::endgroup::"
  record "${name}" "${rc}" "${started}"
}

login_keychain() {
  local login="${HOME}/Library/Keychains/login.keychain-db"
  ls -la "${HOME}/Library/Keychains/"
  stat -f 'login keychain birth=%SB mtime=%Sm' -t '%FT%T' "${login}"
  security list-keychains -d user
  security default-keychain -d user
  step login-keychain-info 20 security show-keychain-info "${login}"
  step login-keychain-write 20 security add-generic-password -U -a probe -s dev.tuist.release-probe -w probe-secret "${login}"
  step login-keychain-read 20 security find-generic-password -s dev.tuist.release-probe -w "${login}"
  step login-keychain-delete 20 security delete-generic-password -s dev.tuist.release-probe "${login}"
}

make_app() {
  local app="${WORK}/Probe.app"
  rm -rf "${app}"
  mkdir -p "${app}/Contents/MacOS"
  printf 'int main(void) { return 0; }\n' > "${WORK}/main.c"
  xcrun clang -o "${app}/Contents/MacOS/Probe" "${WORK}/main.c" || return 1
  cat > "${app}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Probe</string>
<key>CFBundleIdentifier</key><string>dev.tuist.ReleaseProbe</string>
<key>CFBundleName</key><string>Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
</dict></plist>
PLIST
}

codesign_temp_keychain() {
  local keychain="${WORK}/signing.keychain-db" password=probe-keychain-password
  make_app || { record make-app 1 "$(date +%s)"; return; }
  cat > "${WORK}/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Tuist Release Probe
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 2 -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" -config "${WORK}/cert.cnf" 2>&1 | tail -2
  /usr/bin/openssl pkcs12 -export -inkey "${WORK}/key.pem" -in "${WORK}/cert.pem" -out "${WORK}/cert.p12" -passout pass:p12pass 2>&1 | tail -2

  step temp-keychain-create 20 security create-keychain -p "${password}" "${keychain}"
  step temp-keychain-settings 20 security set-keychain-settings -lut 21600 "${keychain}"
  step temp-keychain-unlock 20 security unlock-keychain -p "${password}" "${keychain}"
  step temp-keychain-import 30 security import "${WORK}/cert.p12" -P p12pass -A -t cert -f pkcs12 -k "${keychain}" -T /usr/bin/codesign
  step temp-keychain-partition 30 security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${password}" "${keychain}"
  # shellcheck disable=SC2046
  step temp-keychain-search-list 20 security list-keychains -d user -s "${keychain}" $(security list-keychains -d user | tr -d '"')
  security find-identity -p codesigning "${keychain}"
  local identity
  identity=$(security find-identity -p codesigning "${keychain}" | awk '/Tuist Release Probe/ { print $2; exit }')
  step codesign-sign 60 codesign --force --options runtime --timestamp=none --keychain "${keychain}" -s "${identity}" "${WORK}/Probe.app"
  step codesign-verify 30 codesign --verify --deep --strict --verbose=2 "${WORK}/Probe.app"
  step notarytool-present 30 xcrun notarytool --version
  step stapler-present 30 /bin/bash -c 'xcrun --find stapler'
  security list-keychains -d user -s "${HOME}/Library/Keychains/login.keychain-db"
}

create_dmg() {
  local label=$1 dmg="${WORK}/Probe-${1}.dmg"
  rm -rf "${WORK}/dmg-src" "${dmg}"
  mkdir -p "${WORK}/dmg-src"
  cp -R "${WORK}/Probe.app" "${WORK}/dmg-src/"
  step "create-dmg-${label}" 300 create-dmg \
    --volname "Probe" \
    --window-pos 200 120 \
    --window-size 600 300 \
    --icon-size 100 \
    --icon "Probe.app" 175 120 \
    --hide-extension "Probe.app" \
    --app-drop-link 425 120 \
    --no-internet-enable \
    "${dmg}" "${WORK}/dmg-src/"
  step "dmg-verify-${label}" 60 hdiutil verify "${dmg}"
}

case "${1:-}" in
  login-keychain) login_keychain ;;
  codesign) codesign_temp_keychain ;;
  dmg) create_dmg "${2:?label}" ;;
  *) echo "usage: $0 login-keychain|codesign|dmg <label>" >&2; exit 64 ;;
esac
exit 0
