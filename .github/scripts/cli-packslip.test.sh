#!/usr/bin/env bash
# Exercise release metadata with the real Packslip CLI and offline signing.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow=${WORKFLOW:-$root/.github/workflows/cli-build-publish.yml}
packslip=${PACKSLIP:-packslip}
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
yq -o=json '.' "$workflow" > "$fixture/workflow.json"
inputs=$(jq -c '.jobs["sign-cli"].steps[] | select(.id == "packslip") | .with' "$fixture/workflow.json")
source_commit=1234567890abcdef1234567890abcdef12345678
caller_commit=abcdef1234567890abcdef1234567890abcdef12
archives=(
  artifacts/build/tuist.zip
  artifacts/linux-x86_64/tuist-linux-x86_64.tar.gz
  artifacts/linux-aarch64/tuist-linux-aarch64.tar.gz
)
cd "$fixture"
"$packslip" keygen --out release.key
jq -er '.jobs["sign-cli"].steps[] | select(.name == "Describe CLI release platforms") | .run' workflow.json | bash -euo pipefail

elf() {
  # Minimal ELF64 headers, optionally with PT_INTERP; fixtures are never run.
  local machine=$1 interpreter=${2:-} offset=0000000000000000 count=0000
  if [[ -n "$interpreter" ]]; then
    offset=4000000000000000
    count=0100
  fi
  {
    cat <<EOF
7f454c46020101000000000000000000
0200${machine}01000000
0000000000000000
${offset}
0000000000000000
00000000
40003800${count}400000000000
EOF
    if [[ -n "$interpreter" ]]; then
      printf '03000000040000007800000000000000\n00000000000000000000000000000000\n'
      printf '%02x00000000000000%02x000000000000000100000000000000\n' \
        "$((${#interpreter} + 1))" "$((${#interpreter} + 1))"
    fi
  } | xxd -r -p
  if [[ -n "$interpreter" ]]; then
    printf '%s\0' "$interpreter"
  fi
}

make_archives() {
  mkdir -p artifacts/build artifacts/linux-x86_64 artifacts/linux-aarch64 staging
  printf '#!/bin/sh\nexit 0\n' > staging/tuist
  chmod +x staging/tuist
  (cd staging && zip -q "$fixture/${archives[0]}" tuist)
  elf 3e00 "${1:-}" > staging/tuist
  tar -czf "${archives[1]}" -C staging tuist
  elf b700 "${2:-}" > staging/tuist
  tar -czf "${archives[2]}" -C staging tuist
}

create() {
  local version=$1 input value tag
  local args=(create) files=()
  for input in manifest bin project version tag commit; do
    value=$(jq -er --arg input "$input" '.[$input]' <<< "$inputs")
    # shellcheck disable=SC2016 # Match GitHub expressions literally.
    case "$value" in
      '${{ inputs.version }}') value=$version ;;
      '${{ inputs.ref }}') value=$source_commit ;;
      '${{ github.sha }}') value=$caller_commit ;;
    esac
    args+=("--$input" "$value")
    if [[ "$input" == tag ]]; then tag=$value; fi
  done
  mapfile -t files < <(jq -r '.artifacts | split("\n")[] | select(length > 0)' <<< "$inputs")
  args+=(--source-repo https://github.com/tuist/tuist
    --url-base "https://github.com/tuist/tuist/releases/download/$tag"
    --key release.key --no-log --out packslip "${files[@]}")
  if ! "$packslip" "${args[@]}" > create.log 2>&1; then
    cat create.log >&2
    return 1
  fi
  "$packslip" show packslip/packslip.sigstore.json > statement.json
}

verify() {
  local version=$1 file name digest size
  jq -e --arg version "$version" --arg commit "$source_commit" \
    --argjson x86_libc "$2" --argjson arm_libc "$3" '
    .predicate as $p |
    $p.project == "github.com/tuist/tuist" and $p.version == $version and
    $p.source == {repo: "https://github.com/tuist/tuist", tag: $version, commit: $commit} and
    ($p.artifacts | map({name, os, arch, libc, format}) | sort_by(.name)) == ([
      {name: "tuist.zip", os: "darwin", arch: null, libc: null, format: "zip"},
      {name: "tuist-linux-x86_64.tar.gz", os: "linux", arch: "x86_64", libc: $x86_libc, format: "tar.gz"},
      {name: "tuist-linux-aarch64.tar.gz", os: "linux", arch: "aarch64", libc: $arm_libc, format: "tar.gz"}
    ] | sort_by(.name)) and
    all($p.artifacts[]; .bin == ["tuist"] and
      .url == "https://github.com/tuist/tuist/releases/download/\($version)/\(.name)") and
    (.subject | length) == 3
  ' statement.json > /dev/null || {
    echo "FAIL: incorrect release metadata for $version" >&2
    cat statement.json >&2
    exit 1
  }
  local args=(verify packslip/packslip.sigstore.json --pubkey release.pub --allow-unlogged)
  for file in "${archives[@]}"; do
    name=${file##*/}
    digest=$(sha256sum "$file")
    size=$(wc -c < "$file")
    jq -e --arg name "$name" --arg digest "${digest%% *}" --argjson size "$size" '
      any(.subject[]; .name == $name and .digest.sha256 == $digest) and
      any(.predicate.artifacts[]; .name == $name and .size == $size)
    ' statement.json > /dev/null
    args+=(--artifact "$file")
  done
  "$packslip" "${args[@]}"
}

make_archives /lib64/ld-linux-x86-64.so.2 /lib/ld-musl-aarch64.so.1
for version in 4.214.0 4.214.0-canary.35 4.214.0-rc.1 4.192.1; do
  create "$version"
  verify "$version" '"gnu"' '"musl"'
  echo "ok: $version describes native platforms, libc, source commit, URLs, and signed digests"
done

make_archives
create 4.214.0
verify 4.214.0 null null
echo 'ok: static Linux binaries have no libc requirement'

for file in "${archives[@]}"; do
  mv "$file" "$file.saved"
  if create 4.214.0 > missing.log 2>&1; then
    echo "FAIL: signed a partial release without $file" >&2
    exit 1
  fi
  mv "$file.saved" "$file"
  echo "ok: missing $file prevents signing a partial release"
done

jq -e '
  .jobs["sign-cli"] as $sign | .jobs["publish-cli"] as $publish |
  $sign.permissions == {contents: "read", "id-token": "write"} and
  $sign.env.GITHUB_TOKEN == "${{ github.token }}" and
  $sign.env.MISE_GITHUB_TOKEN == "${{ github.token }}" and
  all($sign.steps[]; (.uses // "" | contains("checkout@") | not)) and
  any($sign.steps[]; .id == "packslip" and (.with.upload | tostring) == "false") and
  ($publish.needs | index("sign-cli")) != null and ($publish | has("if") | not) and
  any($publish.steps[]; (.uses // "" | startswith("softprops/action-gh-release@")) and
    (.with.files | split("\n") | index("build/packslip.sigstore.json")) != null)
' workflow.json > /dev/null
echo 'ok: signing is read-only, receives no release token, and gates publication'
