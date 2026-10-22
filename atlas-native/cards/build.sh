#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
nsh="${NSH_BIN:-nsh}"
case "$("$nsh" --version)" in
  'nsh 0.2.0 '*) ;;
  *) echo 'Thread cards require NSH 0.2.0.' >&2; exit 1 ;;
esac
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
"$nsh" build cards/App.tsx --release --out "$out"
for file in bundle.js app.json capabilities.json; do
  cp "$out/$file" "cards/assets/nsh/$file"
done
python3 cards/verify.py --record
