#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nsh="${NSH_BIN:-nsh}"
case "$("$nsh" --version)" in
  'nsh 0.5.1 '*) ;;
  *) echo 'Customer workspace requires NSH 0.5.1.' >&2; exit 1 ;;
esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp App.tsx Customers.test.tsx nsh.json "$work/"
(
  cd "$work"
  "$nsh" test Customers.test.tsx
  "$nsh" build App.tsx --release --out out
)
cp "$work/out/bundle.js" bundle.js
