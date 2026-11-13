#!/usr/bin/env bash
# Credential-free boundary regressions: every git/gh/minisign call is a fake.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=app/distribution/publish.sh
source "$here/publish.sh"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
export TEST_ROOT=$temp TEST_FAILURE='' TEST_VALUE
TEST_VALUE=$(version "$here/..")
mkdir -p "$temp/assets" "$temp/feed" "$temp/bin"
printf payload > "$temp/assets/Tuist.exe"
printf signature | base64 | tr -d '\n' > "$temp/assets/Tuist.exe.sig"
jq -n --arg version "$TEST_VALUE" '{version:$version,notes:"Notes"}' > "$temp/feed/latest.json"
cp "$temp/assets/Tuist.exe.sig" "$temp/feed/latest.json.sig"
raw=$({ printf Ed; printf '%040d' 0; } | base64 | tr -d '\n')
export DESKTOP_UPDATE_PUBLIC_KEY
DESKTOP_UPDATE_PUBLIC_KEY=$(printf 'untrusted comment: test key\n%s\n' "$raw" | base64 | tr -d '\n')
export GITHUB_REPOSITORY=tuist/tuist GITHUB_REF=refs/heads/main
export GITHUB_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
# PATH fakes make tests safe even when real credentials exist in the environment.
cat > "$temp/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >> "$TEST_ROOT/events"
if [[ $* == 'ls-remote origin refs/heads/main' ]]; then
    if [[ $TEST_FAILURE == advanced ]]; then printf b; else printf '%s' "$GITHUB_SHA"; fi
    printf '\trefs/heads/main\n'
elif [[ $* == 'ls-remote --tags origin '* ]]; then
    if [[ $TEST_FAILURE == existing-tag ]]; then printf 'tag exists\n'; fi
else exit 99
fi
SH
cat > "$temp/bin/minisign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'verify %s\n' "$2" >> "$TEST_ROOT/events"
[[ $TEST_FAILURE != signature ]] || exit 1
if [[ $TEST_FAILURE == payload-signature && $2 == *.exe ]]; then exit 1; fi
SH
cat > "$temp/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh %s\n' "$*" >> "$TEST_ROOT/events"
if [[ $1 == api ]]; then
    [[ $TEST_FAILURE != api ]] || exit 1
    if [[ $* == *releases/tags/desktop-updates ]]; then
        if [[ $TEST_FAILURE == channel ]]; then printf '{"immutable":true,"draft":false,"prerelease":false}';
        else printf '{"immutable":false,"draft":false,"prerelease":false}'; fi
    elif [[ $* == *releases/tags/desktop@* ]]; then
        if [[ $TEST_FAILURE == mutable ]]; then printf '{"immutable":false,"draft":false,"assets":[]}';
        elif [[ $TEST_FAILURE == missing-asset ]]; then printf '{"immutable":true,"draft":false,"assets":[]}';
        else printf '{"immutable":true,"draft":false,"assets":[{"name":"Tuist.exe"},{"name":"Tuist.exe.sig"}]}'; fi
    elif [[ $* == *releases?per_page=100 ]]; then
        if [[ $TEST_FAILURE == existing-draft ]]; then
            jq -n --arg tag "desktop@$TEST_VALUE" '[[{tag_name:$tag,draft:true}]]'
        else printf '[]'; fi
    else exit 99
    fi
elif [[ $1 == release ]]; then
    case $2 in
        create|upload|edit) [[ $TEST_FAILURE != "$2" ]] || exit 1;;
        download)
            [[ $TEST_FAILURE != download ]] || exit 1
            while [[ $1 != --dir ]]; do shift; done
            cp "$TEST_ROOT/assets/"* "$2/"
            if [[ $TEST_FAILURE == readback ]]; then printf tampered > "$2/Tuist.exe"; fi;;
        *) exit 99;;
    esac
else exit 99
fi
SH
chmod +x "$temp/bin/"*
export PATH="$temp/bin:$PATH"

bash "$here/publish.sh" --assets "$temp/assets" --feed "$temp/feed" --sha "$GITHUB_SHA"
edit=$(grep -n '^gh release edit ' "$temp/events" | cut -d: -f1)
immutable=$(grep -n '^gh api repos/tuist/tuist/releases/tags/desktop@' "$temp/events" | cut -d: -f1)
readback=$(grep -n '^gh release download ' "$temp/events" | cut -d: -f1)
feed=$(grep -n '^gh release upload desktop-updates ' "$temp/events" | cut -d: -f1)
[[ $edit -lt $immutable && $immutable -lt $readback && $readback -lt $feed ]]
[[ $(grep -c '^verify ' "$temp/events") == 2 ]]
grep -Fq -- "$temp/feed/latest.json $temp/feed/latest.json.sig" "$temp/events"
printf 'PASS: authenticated immutable publication and readback precede feed\n'

for TEST_FAILURE in existing-tag existing-draft api channel mutable missing-asset readback advanced signature payload-signature create upload edit download; do
    export TEST_FAILURE
    : > "$temp/events"
    if bash "$here/publish.sh" --assets "$temp/assets" --feed "$temp/feed" --sha "$GITHUB_SHA" > "$temp/output" 2>&1; then
        printf 'FAIL: accepted %s\n' "$TEST_FAILURE" >&2; exit 1
    fi
    if grep -q '^gh release upload desktop-updates ' "$temp/events"; then
        printf 'FAIL: feed touched for %s\n' "$TEST_FAILURE" >&2; exit 1
    fi
done
printf 'PASS: 14 boundary failures leave feed untouched\n'
export TEST_FAILURE=
for bad in branch sha repository; do
    : > "$temp/events"
    if (case $bad in branch) export GITHUB_REF=refs/heads/untrusted;; sha) export GITHUB_SHA=bad;; repository) export GITHUB_REPOSITORY=other/repo;; esac
        exec bash "$here/publish.sh" --assets "$temp/assets" --feed "$temp/feed" --sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    ) > "$temp/output" 2>&1; then printf 'FAIL: accepted untrusted %s\n' "$bad"; exit 1; fi
    [[ ! -s $temp/events ]]
done
printf 'PASS: untrusted branch/repository/SHA never invoke remote tools\n'
if bash -c 'source "$1"; verify "$2" "not base64"' _ "$here/publish.sh" "$temp/feed/latest.json" > "$temp/output" 2>&1; then
    printf 'FAIL: invalid key accepted\n'; exit 1
fi
printf 'PASS: malformed key rejected before verification\n'
