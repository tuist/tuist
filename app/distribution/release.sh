#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BINARY=cargo_tuist_desktop_bin_Tuist
FLAGS='["-C","opt-level=3","-C","debuginfo=0"]'

fail() { printf '%s\n' "$*" >&2; exit 1; }
required() { test -n "${!1:-}" || fail "Provision $1 before releasing"; }
decode() {
    local value
    value=$(tr -d '\r\n')
    [[ $value =~ ^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$ ]] || fail 'Invalid base64'
    printf '%s' "$value" | openssl base64 -d -A
}
query() { (cd "$1"; shift; once --format json query "$@"); }

toml() {
    jq -r 'def value:
      if type == "object" then "{ " + (to_entries | map((.key | tojson) + " = " + (.value | value)) | join(", ")) + " }"
      elif type == "array" then "[" + (map(value) | join(", ")) + "]"
      else tojson end;
      to_entries | map((.key | tojson) + " = " + (.value | value)) | join("\n")'
}

public_key() {
    local value=$1 output=$2
    printf '%s' "$value" | decode > "$output"
    test "$(awk 'END {print NR}' "$output")" = 2 || fail 'Expected minisign public key box'
    head -n 1 "$output" | grep -q '^untrusted comment:' || fail 'Expected minisign public key comment'
    tail -n 1 "$output" | decode > "$output.raw"
    test "$(wc -c < "$output.raw" | tr -d ' ')" = 42 || fail 'Invalid minisign public key length'
    case $(head -c 2 "$output.raw") in Ed|ED) ;; *) fail 'Invalid minisign public key algorithm';; esac
    rm "$output.raw"
}

version() {
    local root=$1 value
    value=$(yq -p toml -r '.workspace.package.version' "$root/Cargo.toml")
    [[ $value =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'Stable desktop releases require X.Y.Z'
    yq -p toml -o json '.' "$root/Cargo.lock" | jq -e --arg version "$value" '
      [.package[] | select((.name | startswith("tuist-")) and (has("source") | not))] |
      length > 0 and all(.[]; .version == $version)' >/dev/null || fail 'Cargo.lock tuist-* versions must equal workspace.package.version'
    printf '%s\n' "$value"
}

stamp() (
    local root=$1 key=$2 kind=$3 value temp
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    public_key "$key" "$temp/key"
    value=$(version "$root") || exit 1
    test -f "$root/crates/updater/src/public-key.txt" && test -f "$root/crates/updater/src/package-kind.txt" || fail 'Missing updater build input'
    printf '%s\n' "$key" > "$root/crates/updater/src/public-key.txt"
    printf '%s\n' "$kind" > "$root/crates/updater/src/package-kind.txt"
    printf '%s\n' "$value"
)

optimize_graph() (
    local root=$1 temp id
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    query "$root" schema cargo_dependencies | jq -e '.attrs | any(.name == "dep_rustc_flags")' >/dev/null || fail 'Once optimization schema changed'
    # Native Windows jq otherwise writes CRLF, making Bash read CR as part of each ID.
    query "$root" 'MATCH (t:Target) WHERE t.id STARTS WITH "cargo_" RETURN t.id, t.kind' | jq -br '.rows[][0]' > "$temp/ids"
    while IFS= read -r id; do query "$root" target "$id"; done < "$temp/ids" | jq -s '.' > "$temp/targets"
    jq -e --arg binary "$BINARY" 'any(.[]; .label.id == $binary)' "$temp/targets" >/dev/null || fail 'Once did not declare the desktop binary'
    yq -p toml -o json '.' "$root/once.toml" > "$temp/seed"
    (cd "$root"; cargo vendor --locked --versioned-dirs third_party/rust/vendor > /dev/null)
    jq -n --slurpfile seed "$temp/seed" --slurpfile targets "$temp/targets" --argjson flags "$FLAGS" '
      {workspace:{include:["once.toml"],exclude:["**/Cargo.toml"]}, infrastructure:{cache:{provider:"local"}},
       target: ([{name:"DesktopDependencies",kind:"cargo_dependencies",srcs:$seed[0].target[0].srcs,
         attrs:($seed[0].target[0].attrs + {dep_rustc_flags:$flags,vendor_dir:"third_party/rust/vendor"})}] +
         [$targets[0][] | {name:.label.name,kind,srcs,deps,attrs:(.attrs + {rustc_flags:$flags})}])}' |
      toml > "$root/once.toml"
    query "$root" validate-workspace | jq -e '.valid' >/dev/null || fail 'Invalid optimized Once graph'
    while IFS= read -r id; do
        query "$root" target "$id" | jq -e --argjson flags "$FLAGS" '.attrs.rustc_flags == $flags' >/dev/null || fail 'Once dropped first-party optimization flags'
    done < "$temp/ids"
    query "$root" 'MATCH (t:Target) WHERE t.kind IN ["rust_crate", "rust_proc_macro"] RETURN t.id, t.attrs.rustc_flags' |
      jq -e --argjson flags "$FLAGS" '.rows | length > 0 and all(.[]; .[1] == $flags)' >/dev/null || fail 'Once dropped dependency optimization flags'
)

icon() {
    local png=$1 destination=$2 size shift
    test "$(od -An -tx1 -N8 "$png" | tr -d ' \n')" = 89504e470d0a1a0a || fail 'Expected PNG icon'
    test "$(od -An -tx1 -j16 -N8 "$png" | tr -d ' \n')" = 0000010000000100 || fail 'Expected 256px icon'
    size=$(wc -c < "$png")
    {
        printf '\000\000\001\000\001\000\000\000\000\000\001\000\040\000'
        for shift in 0 8 16 24; do printf '%b' "\\$(printf '%03o' "$(((size >> shift) & 255))")"; done
        printf '\026\000\000\000'
        cat "$png"
    } > "$destination"
}

config() {
    local stage=$1 target=$2 value=$3 release=$4 fmt=appimage
    test "$target" != windows-x86_64 || fmt=nsis
    jq -n --arg stage "$stage" --arg version "$value" --arg fmt "$fmt" '
      {name:"tuist-desktop",productName:"Tuist",version:$version,identifier:"dev.tuist.desktop",publisher:"Tuist",
       description:"Tuist desktop companion",category:"DeveloperTool",homepage:"https://tuist.dev",formats:[$fmt],
       binaries:[{path:"Tuist",main:true}],binariesDir:($stage+"/bin"),outDir:($stage+"/packages"),
       icons:[($stage+"/icon.png"),($stage+"/icon.ico")],deepLinkProtocols:[{schemes:["tuist"]}]}' > "$stage/packager.json"
    if test "$fmt" = nsis; then
        jq --arg stage "$stage" --rawfile hook "$ROOT/distribution/nsis-hooks.nsh" '
          . + {resources:[{src:($stage+"/tuist-installation"),target:"tuist-installation"}],
           nsis:{installMode:"currentUser",installerIcon:($stage+"/icon.ico"),languages:["English"],preinstallSection:$hook},windows:{allowDowngrades:false}}' \
          "$stage/packager.json" > "$stage/config.tmp"
        mv "$stage/config.tmp" "$stage/packager.json"
        if test "$release" = true; then
            required DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT
            required DESKTOP_WINDOWS_TIMESTAMP_URL
            [[ $DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT =~ ^[A-Fa-f0-9]{40}$ ]] || fail 'Require approved Authenticode certificate SHA1 thumbprint'
            [[ $DESKTOP_WINDOWS_TIMESTAMP_URL == https://* ]] || fail 'Require HTTPS Authenticode timestamp server'
            jq --arg thumb "$DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT" --arg url "$DESKTOP_WINDOWS_TIMESTAMP_URL" '
              .windows += {certificateThumbprint:$thumb,digestAlgorithm:"sha256",timestampUrl:$url,tsp:true}' \
              "$stage/packager.json" > "$stage/config.tmp"
            mv "$stage/config.tmp" "$stage/packager.json"
        fi
    fi
}

verify() (
    local path=$1 key=$2 temp
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    public_key "$key" "$temp/key"
    decode < "$path.sig" > "$temp/sig"
    minisign -Vm "$path" -p "$temp/key" -x "$temp/sig"
)

sign() {
    required CARGO_PACKAGER_SIGN_PRIVATE_KEY
    test "${CARGO_PACKAGER_SIGN_PRIVATE_KEY_PASSWORD+x}" = x || fail 'Provision signing password (may be empty)'
    cargo-packager signer sign "$1"
    verify "$1" "$2"
}

check_tools() {
    local expected actual
    expected=$(yq -p toml -r '.tools."github:tuist/once"' "$ROOT/mise.toml")
    actual=$(once --version)
    test "$actual" = "once $expected" || fail "Require Once $expected; got $actual"
    test "$(cargo-packager --version)" = 'cargo-packager 0.11.7' || fail 'Require cargo-packager 0.11.7'
}

build() (
    local stage=$1 release=$2 target fmt root value key='' binary payload name
    check_tools
    case $(uname -s) in Linux) target=linux-x86_64; fmt=appimage;; MINGW*|MSYS*) target=windows-x86_64; fmt=nsis;; *) fail 'Package natively on Linux/Windows x86_64 only';; esac
    case $(uname -m) in x86_64|amd64|AMD64) ;; *) fail 'Package natively on x86_64 only';; esac
    mkdir -p "$(dirname "$stage")"
    mkdir "$stage"
    if test "$fmt" = nsis; then stage=$(cd "$stage" && pwd -W); else stage=$(cd "$stage" && pwd); fi
    value=$(version "$ROOT")
    config "$stage" "$target" "$value" "$release"
    root=$stage/source
    mkdir "$root"
    cp "$ROOT/Cargo.toml" "$ROOT/Cargo.lock" "$root/"
    cp -R "$ROOT/gpui" "$ROOT/crates" "$root/"
    # Packaging needs only the Cargo graph, not native frontend rules or prepared SDK dependencies.
    yq -p toml -o json '.' "$ROOT/once.toml" |
        jq '.workspace.include = ["once.toml"] | del(.modules) | .target |= map(select(.name == "TuistDesktop"))' |
        toml > "$root/once.toml"
    value=$(version "$root")
    if test "$release" = true; then
        required DESKTOP_UPDATE_PUBLIC_KEY
        key=$DESKTOP_UPDATE_PUBLIC_KEY
        stamp "$root" "$key" "$fmt" >/dev/null
        required CARGO_PACKAGER_SIGN_PRIVATE_KEY
        test "${CARGO_PACKAGER_SIGN_PRIVATE_KEY_PASSWORD+x}" = x || fail 'Missing signing password variable'
    else
        printf '%s\n' "$fmt" > "$root/crates/updater/src/package-kind.txt"
    fi
    export ONCE_CACHE_PROVIDER=local
    # Concurrent Once test batches remove and recreate shared per-package
    # outputs (`.once/out/<package>/deps-rlib-search`). Windows fails on that
    # race, so run its batches one at a time.
    jobs=
    test "$fmt" != nsis || jobs=1
    # GPUI keyboard/layout tests require debug-only bounds instrumentation.
    # Test the staged sources before switching the graph to shipping flags.
    (
        cd "$root"
        if once test --all ${jobs:+--jobs "$jobs"}; then :; else
            status=$?
            for log in .once/out/*/test/rust-libtest.log; do
                test -f "$log" || continue
                printf '\n--- %s ---\n' "$log"
                cat "$log"
            done
            exit "$status"
        fi
    )
    optimize_graph "$root"
    (cd "$root"; once build "$BINARY")
    name=Tuist
    test "$fmt" != nsis || name=Tuist.exe
    binary=$root/.once/out/$BINARY/$name
    test -f "$binary" && test ! -L "$binary" || fail 'Expected native Once declared binary output'
    mkdir "$stage/bin"
    cp "$binary" "$stage/bin/$name"
    cp "$ROOT/gpui/resources/icon.png" "$stage/icon.png"
    icon "$stage/icon.png" "$stage/icon.ico"
    printf 'nsis\n' > "$stage/tuist-installation"
    (
        while IFS= read -r name; do unset "$name"; done < <(compgen -A variable CARGO_PACKAGER_SIGN_)
        cargo-packager --config "$stage/packager.json"
    )
    shopt -s nullglob
    local packages=()
    if test "$fmt" = nsis; then packages=("$stage/packages/"*.exe); else packages=("$stage/packages/"*.AppImage); fi
    test "${#packages[@]}" = 1 || fail 'Expected exactly one native package'
    payload=${packages[0]}
    if test "$fmt" = nsis && test "$release" = true; then
        powershell -NoProfile -File "$ROOT/distribution/verify-authenticode.ps1" -Path "$payload" -Thumbprint "$DESKTOP_WINDOWS_CERTIFICATE_THUMBPRINT"
    fi
    mkdir "$stage/assets"
    cp "$payload" "$stage/assets/"
    test -z "$key" || sign "$stage/assets/$(basename "$payload")" "$key"
    jq -n --arg version "$value" --arg target "$target" --arg fmt "$fmt" --arg payload "$(basename "$payload")" --argjson signed "$release" \
      '{version:$version,target:$target,format:$fmt,payload:$payload,signed:$signed}' | tee "$stage/assets/$target.json"
)

feed() (
    local directory=$1 output=$2 key=$3 notes=$4 temp value target fmt name path signature
    temp=$(mktemp -d)
    trap 'rm -rf "$temp"' EXIT
    jq -se 'length == 2 and ([.[].version] | unique | length == 1)' "$directory/linux-x86_64.json" "$directory/windows-x86_64.json" >/dev/null || fail 'Platform versions differ'
    value=$(jq -r .version "$directory/linux-x86_64.json")
    [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Invalid release version'
    jq -n --arg version "$value" --arg notes "$notes" '{version:$version,notes:$notes,platforms:{}}' > "$temp/feed"
    for target in linux-x86_64 windows-x86_64; do
        fmt=appimage
        test "$target" != windows-x86_64 || fmt=nsis
        jq -e --arg target "$target" --arg fmt "$fmt" '.target == $target and .format == $fmt and .signed == true' "$directory/$target.json" >/dev/null || fail 'Wrong or unsigned platform'
        name=$(jq -er .payload "$directory/$target.json")
        [[ $name =~ ^[A-Za-z0-9_.-]+$ ]] && [[ $name != . && $name != .. ]] || fail 'Unsafe payload name'
        case "$fmt:$name" in appimage:*.AppImage|nsis:*.exe) ;; *) fail 'Wrong updater payload extension';; esac
        path=$directory/$name
        verify "$path" "$key"
        signature=$(cat "$path.sig")
        jq --arg target "$target" --arg fmt "$fmt" --arg signature "$signature" \
          --arg url "https://github.com/tuist/tuist/releases/download/desktop@$value/$name" \
          '.platforms[$target] = {url:$url,signature:$signature,format:$fmt}' "$temp/feed" > "$temp/next"
        mv "$temp/next" "$temp/feed"
    done
    mkdir -p "$(dirname "$output")"
    cp "$temp/feed" "$output"
    sign "$output" "$key"
    (cd "$directory"; for path in *; do
        test -f "$path" && test "$path" != SHA256SUMS || continue
        if command -v sha256sum >/dev/null; then sha256sum "$path"; else shasum -a 256 "$path"; fi
    done) > "$temp/checksums"
    cp "$temp/checksums" "$directory/SHA256SUMS"
    printf '%s\n' "$value"
)

main() {
    local command=${1:-} output='' assets='' notes='' release=false
    test $# -gt 0 || fail 'Usage: release.sh build --output PATH [--release] | feed --assets PATH --output PATH [--notes TEXT]'
    shift
    while test $# -gt 0; do
        case $1 in
            --output|--assets|--notes) test $# -ge 2 || fail "Missing value for $1"; case $1 in --output) output=$2;; --assets) assets=$2;; --notes) notes=$2;; esac; shift 2;;
            --release) release=true; shift;;
            *) fail "Unknown argument: $1";;
        esac
    done
    test -n "$output" || fail 'Require --output'
    case $command in
        build) build "$output" "$release";;
        feed) test -n "$assets" || fail 'Require --assets'; required DESKTOP_UPDATE_PUBLIC_KEY; feed "$assets" "$output" "$DESKTOP_UPDATE_PUBLIC_KEY" "$notes";;
        *) fail 'Expected build or feed';;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
