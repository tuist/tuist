#!/usr/bin/env bash
# Portable to the macOS system Bash; only OpenSSL and awk are required.
set -euo pipefail

policy="$(cd "$(dirname "$0")" && pwd)/policy.json"
usage() { echo "usage: $0 check FILE... | filter SOURCE DESTINATION | extract-blocked SOURCE DIRECTORY" >&2; exit 2; }
[[ $# -ge 2 ]] || usage
mode="$1"
shift
case "$mode" in
  check) ;;
  filter|extract-blocked) [[ $# -eq 2 ]] || usage ;;
  *) usage ;;
esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
awk -F '"' '
  /"key_count":/ { value=$0; gsub(/[^0-9]/, "", value); expected=value+0 }
  /"distrusted_spki_sha256": *\[/ { active=1; next }
  active && /\]/ { active=0; closed=1; next }
  active {
    if (length($2) != 64 || $2 ~ /[^a-f0-9]/ || seen[$2]++) invalid=1
    print $2; count++
  }
  END { if (invalid || !closed || expected < 2 || count != expected) exit 1 }
' "$policy" > "$work/blocked" || { echo "invalid distrust policy" >&2; exit 1; }

split_certificates() {
  if grep -q '^-----BEGIN .*PRIVATE KEY-----$' "$1"; then
    echo "refusing a CA store containing private-key material" >&2
    exit 1
  fi
  mkdir "$work/certs"
  awk -v dir="$work/certs" '
    /^-----BEGIN (TRUSTED )?CERTIFICATE-----$/ {
      if (active) exit 1
      active=1; count++; file=dir "/cert-" count ".pem"
    }
    active { print > file }
    /^-----END (TRUSTED )?CERTIFICATE-----$/ {
      if (!active) exit 1
      active=0; close(file)
    }
    END { if (active || !count) exit 1 }
  ' "$1"
}

status=0
for input in "$@"; do
  [[ -r "$input" ]] || { echo "unreadable store: $input" >&2; exit 1; }
  split_certificates "$input"
  : > "$work/clean"
  kept=0
  for certificate in "$work"/certs/cert-*.pem; do
    hash="$(openssl x509 -in "$certificate" -pubkey -noout |
      openssl pkey -pubin -outform DER | openssl dgst -sha256 | awk '{print $NF}')"
    [[ ${#hash} -eq 64 ]] || { echo "invalid certificate in $input" >&2; exit 1; }
    if grep -Fxq "$hash" "$work/blocked"; then
      echo "distrusted SPKI $hash in $input" >&2
      status=1
      if [[ "$mode" == filter ]] && grep -q '^-----BEGIN TRUSTED CERTIFICATE-----' "$certificate"; then
        echo 'TRUSTED CERTIFICATE attributes require dedicated qualification; preserve explicit distrust' >&2
        exit 1
      fi
      if [[ "$mode" == extract-blocked ]]; then
        mkdir -p "$2"
        cp "$certificate" "$2/$hash.pem"
      fi
    else
      cat "$certificate" >> "$work/clean"
      kept=$((kept + 1))
    fi
  done
  if [[ "$mode" == filter ]]; then
    [[ $kept -gt 0 ]] || { echo "refusing to empty CA bundle" >&2; exit 1; }
    [[ ! "$input" -ef "$2" ]] || { echo "filter destination must differ from source" >&2; exit 1; }
    cp "$work/clean" "$2"
  fi
  rm -rf "$work/certs"
  [[ "$mode" == check ]] || exit 0
done
exit "$status"
