#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=release.sh
source "$HERE/release.sh"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/project/crates/updater/src" "$temp/config" "$temp/bin"
printf '[workspace.package]\nversion="1.2.3"\n' > "$temp/project/Cargo.toml"
printf '[[package]]\nname="tuist-desktop"\nversion="1.2.3"\n' > "$temp/project/Cargo.lock"
touch "$temp/project/crates/updater/src/"{public-key,package-kind}.txt
key=$( { printf 'untrusted comment: test\n'; { printf Ed; dd if=/dev/zero bs=40 count=1 2>/dev/null; } | openssl base64 -A; printf '\n'; } | openssl base64 -A)
test "$(stamp "$temp/project" "$key" nsis)" = 1.2.3
test "$(cat "$temp/project/crates/updater/src/public-key.txt")" = "$key"
test "$(cat "$temp/project/crates/updater/src/package-kind.txt")" = nsis
sed 's/1.2.3/1.2.2/' "$temp/project/Cargo.lock" > "$temp/lock"
mv "$temp/lock" "$temp/project/Cargo.lock"
if (stamp "$temp/project" "$key" appimage) >/dev/null 2>&1; then fail 'Accepted mismatched lockfile'; fi
for invalid in '' invalid bm90IGEga2V5; do
    if (public_key "$invalid" "$temp/key") >/dev/null 2>&1; then fail 'Accepted invalid key'; fi
done
rm "$temp/project/crates/updater/src/public-key.txt"
if (stamp "$temp/project" "$key" appimage) >/dev/null 2>&1; then fail 'Accepted missing source input'; fi
echo 'PASS updater stamping and version/key rejection'

config "$temp/config" windows-x86_64 1.2.3 false
jq -e '.nsis.installMode == "currentUser" and .deepLinkProtocols == [{schemes:["tuist"]}] and .resources[0].target == "tuist-installation" and (.nsis.preinstallSection | contains("Function un.onUninstSuccess")) and (has("beforePackagingCommand") | not)' "$temp/config/packager.json" >/dev/null
if (unset DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT DESKTOP_WINDOWS_TIMESTAMP_URL; config "$temp/config" windows-x86_64 1.2.3 true) >/dev/null 2>&1; then fail 'Accepted missing Authenticode config'; fi
(export DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA DESKTOP_WINDOWS_TIMESTAMP_URL=https://timestamp.example; config "$temp/config" windows-x86_64 1.2.3 true)
jq -e '.windows.certificateThumbprint == "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" and .windows.tsp == true' "$temp/config/packager.json" >/dev/null
echo 'PASS native packager configuration and signing guard'

icon "$ROOT/gpui/resources/icon.png" "$temp/icon.ico"
dd if="$temp/icon.ico" of="$temp/icon.png" bs=1 skip=22 2>/dev/null
cmp "$ROOT/gpui/resources/icon.png" "$temp/icon.png"
test "$(od -An -tx1 -N6 "$temp/icon.ico" | tr -d ' \n')" = 000001000100
echo 'PASS brand PNG retained in ICO'

yq -p toml -o json '.' "$ROOT/once.toml" | toml | yq -p toml -o json '.' > "$temp/roundtrip"
yq -p toml -o json '.' "$ROOT/once.toml" > "$temp/original"
jq -en --slurpfile original "$temp/original" --slurpfile roundtrip "$temp/roundtrip" '$original == $roundtrip' >/dev/null
echo 'PASS TOML source mappings round-trip'

pin=$(yq -p toml -r '.tools."github:tuist/once"' "$ROOT/mise.toml")
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\nprintf "once %%s\\n" "${TEST_ONCE_VERSION}"\n' > "$temp/bin/once"
printf '#!/usr/bin/env bash\necho "cargo-packager 0.11.7"\n' > "$temp/bin/cargo-packager"
chmod +x "$temp/bin/"*
PATH="$temp/bin:$PATH" TEST_ONCE_VERSION="$pin" check_tools
if (PATH="$temp/bin:$PATH" TEST_ONCE_VERSION=0.75.0 check_tools) >/dev/null 2>&1; then fail 'Accepted obsolete Once version'; fi
echo 'PASS packaging agrees with mise pin and rejects stale tool'

cat > "$temp/bin/once" <<'ONCE'
#!/usr/bin/env bash
set -euo pipefail
if test "$1" = --version; then printf 'once %s\n' "$TEST_ONCE_VERSION"; exit; fi
test "$1 $2" = 'test --all'
yq -p toml -o json '.' once.toml | jq -e '
    .workspace.include == ["once.toml"] and (has("modules") | not) and
    (.target | length == 1) and .target[0].name == "TuistCodeDesktop" and
    .target[0].kind == "cargo_workspace" and
    .target[0].attrs.resolver_inputs == ["Cargo.toml", "Cargo.lock", "gpui/Cargo.toml", "crates/*/Cargo.toml"]' >/dev/null
test -f gpui/Cargo.toml && test -f crates/core/Cargo.toml && test -f Cargo.lock
test ! -d native-dependencies && test ! -d modules && test ! -d android
printf 'PASS isolated desktop packaging workspace\n' > "$TEST_PACKAGING_MARKER"
# Stop before compilation/packaging; the real build must propagate this failure.
exit 73
ONCE
# Do not invoke build in an if-condition: Bash would disable its errexit handling.
set +e
(set -e; PATH="$temp/bin:$PATH" TEST_ONCE_VERSION="$pin" TEST_PACKAGING_MARKER="$temp/staged" build "$temp/package" false)
status=$?
set -e
test "$status" = 73 || fail 'Packaging failed before reaching the isolated graph test'
cat "$temp/staged"

mkdir "$temp/assets"
for target in linux-x86_64 windows-x86_64; do
    fmt=appimage; name=TuistCode_1.2.3.AppImage
    if test "$target" = windows-x86_64; then fmt=nsis; name=TuistCode_1.2.3.exe; fi
    printf payload > "$temp/assets/$name"
    printf signature > "$temp/assets/$name.sig"
    jq -n --arg target "$target" --arg fmt "$fmt" --arg name "$name" '{version:"1.2.3",target:$target,format:$fmt,signed:true,payload:$name}' > "$temp/assets/$target.json"
done
(
    verify() { test -f "$1" && test "$2" = "$key"; }
    sign() { printf feed-signature > "$1.sig"; }
    feed "$temp/assets" "$temp/feed/latest.json" "$key" Notes >/dev/null
)
jq -e '.version == "1.2.3" and .notes == "Notes" and (.platforms | length == 2) and .platforms["linux-x86_64"].format == "appimage" and .platforms["windows-x86_64"].url == "https://github.com/tuist/tuist/releases/download/desktop@1.2.3/TuistCode_1.2.3.exe"' "$temp/feed/latest.json" >/dev/null
if grep -q SHA256SUMS "$temp/assets/SHA256SUMS"; then fail 'Checksums include themselves'; fi
cp "$temp/assets/linux-x86_64.json" "$temp/record"
for mutation in '.signed=false' '.target="windows-x86_64"' '.version="1.2.4"' '.payload="../other.AppImage"' '.format="deb"'; do
    jq "$mutation" "$temp/record" > "$temp/assets/linux-x86_64.json"
    if (verify() { :; }; sign() { :; }; feed "$temp/assets" "$temp/feed/latest.json" "$key" '') >/dev/null 2>&1; then fail "Accepted invalid feed: $mutation"; fi
done
echo 'PASS feed artifacts and rejection of unsigned/mismatched/traversal records'

if command -v minisign >/dev/null && command -v cargo-packager >/dev/null; then
    cargo-packager signer generate --password '' --path "$temp/signing"
    key=$(cat "$temp/signing.pub")
    export CARGO_PACKAGER_SIGN_PRIVATE_KEY CARGO_PACKAGER_SIGN_PRIVATE_KEY_PASSWORD=''
    CARGO_PACKAGER_SIGN_PRIVATE_KEY=$(cat "$temp/signing")
    printf original > "$temp/payload"
    sign "$temp/payload" "$key"
    printf tampered > "$temp/payload"
    if (verify "$temp/payload" "$key") >/dev/null 2>&1; then fail 'Accepted tampered signature'; fi
    printf original > "$temp/payload"
    cargo-packager signer generate --password '' --path "$temp/other"
    if (verify "$temp/payload" "$(cat "$temp/other.pub")") >/dev/null 2>&1; then fail 'Accepted wrong signing key'; fi
    echo 'PASS real offline signer rejects tampering and wrong key'
else
    echo 'SKIP real signer checks: install minisign and cargo-packager 0.11.7'
fi
