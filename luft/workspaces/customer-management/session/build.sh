#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
nsh="${NSH_BIN:-nsh}"
case "$("$nsh" --version)" in
  'nsh 0.5.1 '*) ;;
  *) echo 'Session harness requires NSH 0.5.1.' >&2; exit 1 ;;
esac
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/luft/apps/support/ui" "$work/luft/workspaces/customer-management/session"
cp ../../../apps/support/ui/Support.tsx "$work/luft/apps/support/ui/"
cp App.tsx Session.test.tsx nsh.json "$work/luft/workspaces/customer-management/session/"
(
  cd "$work/luft/workspaces/customer-management/session"
  "$nsh" test Session.test.tsx
  "$nsh" build App.tsx --release --out out
)
cp "$work/luft/workspaces/customer-management/session/out/bundle.js" session-bundle.js
