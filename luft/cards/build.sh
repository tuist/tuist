#!/usr/bin/env bash
# Rebuilds bundle.js from App.tsx and the server's card kit, with the NSH
# version the Apple SDK pins (modules/nsh.star). Commit both together.
set -euo pipefail
cd "$(dirname "$0")"
nsh="${NSH_BIN:-nsh}"
case "$("$nsh" --version)" in
  'nsh 0.5.1 '*) ;;
  *) echo 'Luft cards require NSH 0.5.1.' >&2; exit 1 ;;
esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# As the server builds cards: the kit beside the card, as "./luft".
cp App.tsx nsh.json "$work/"
cp ../../server/priv/threads/card_kit.tsx "$work/luft.tsx"
(
  cd "$work"
  echo 'await app.press("Ask why TuistKit misses")' | "$nsh" test App.tsx
  "$nsh" build App.tsx --release --out out
)
cp "$work/out/bundle.js" bundle.js
