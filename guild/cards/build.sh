#!/usr/bin/env bash
# Rebuilds bundle.js from App.tsx with the NSH version the Apple SDK pins
# (modules/nsh.star). Commit both together.
set -euo pipefail
cd "$(dirname "$0")"
nsh="${NSH_BIN:-nsh}"
case "$("$nsh" --version)" in
  'nsh 0.5.1 '*) ;;
  *) echo 'Guild cards require NSH 0.5.1.' >&2; exit 1 ;;
esac
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
echo 'await app.press("Ask why TuistKit misses")' | "$nsh" test App.tsx
"$nsh" build App.tsx --release --out "$out"
cp "$out/bundle.js" bundle.js
