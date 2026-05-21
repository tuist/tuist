#!/usr/bin/env bash
#MISE description "Refresh the Apple session cookies used by the Tuist.XcodeMirror worker."
#USAGE arg "[apple_id]" help="Apple ID to sign in as (default: read from 1Password)."

# Quarterly maintenance for the Tuist.XcodeMirror worker. Apple's
# developer.apple.com session expires every ~30 days; when the
# worker hits a 401 it Sentry-emits `xcode_mirror.session_expired`
# with a link to this task.
#
# Flow:
#   1. Spawn `xcodes signin <apple-id>` — interactive 2FA on a
#      trusted device. The session lands in your login keychain.
#   2. Read the just-stored session cookies out of the keychain.
#   3. Write the JSON cookie jar straight into the 1Password
#      `Tuist Xcode Mirror Session` item via `op item edit`.
#   4. External Secrets propagates the updated value into the
#      cluster within ~5 min; the next worker tick uses the fresh
#      cookies.
#
# No SSH into any host. No paste step. Any maintainer's Mac that
# has `op`, `xcodes`, and `jq` works.

set -euo pipefail

OP_VAULT="${TUIST_XCODE_MIRROR_OP_VAULT:-Engineering}"
OP_ITEM="${TUIST_XCODE_MIRROR_OP_ITEM:-Tuist Xcode Mirror Session}"
OP_FIELD="${TUIST_XCODE_MIRROR_OP_FIELD:-session_cookies}"
KEYCHAIN_SERVICE="${TUIST_XCODE_MIRROR_KEYCHAIN_SERVICE:-xcodes}"

for cmd in op xcodes jq security; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: ${cmd} not on PATH. Install: brew install 1password-cli xcodes jq" >&2
    exit 1
  fi
done

# `op whoami` exits non-zero if the CLI isn't signed in. Fail with
# a clear message so the operator doesn't sit through xcodes auth
# only to hit a 1P-auth wall.
if ! op whoami >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Error: 1Password CLI not signed in.
Run: eval "$(op signin)"
(Or enable the desktop-app integration: 1Password → Settings → Developer → "Integrate with 1Password CLI".)
EOF
  exit 1
fi

APPLE_ID="${usage_apple_id:-${1:-}}"
if [ -z "$APPLE_ID" ]; then
  # Fall back to the 1Password item — the same vault item stores
  # the Apple ID alongside the session cookies for exactly this
  # bootstrap.
  APPLE_ID="$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields apple_id 2>/dev/null || true)"
fi

if [ -z "$APPLE_ID" ]; then
  echo "Error: no Apple ID configured. Pass as argument or set apple_id field on 1Password item '$OP_ITEM'." >&2
  exit 1
fi

echo "Signing in to xcodes as $APPLE_ID..."
echo "(You'll get a 2FA prompt on your trusted Apple device — approve it, then enter the 6-digit code below.)"
echo

# `xcodes signin` is interactive: it'll prompt for password and
# 2FA. We let stdin/stdout flow through so the operator can
# respond.
xcodes signin "$APPLE_ID"

echo
echo "Reading session cookies from keychain..."

# xcodes stores its session as a JSON blob keyed by the Apple ID,
# under the `xcodes` keychain service. The format isn't a public
# contract — be defensive about the shape: if it's not a JSON
# object with at least one cookie-shaped value, bail.
raw_session=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$APPLE_ID" -w 2>/dev/null || true)

if [ -z "$raw_session" ]; then
  echo "Error: no '$KEYCHAIN_SERVICE' keychain entry for $APPLE_ID after signin." >&2
  echo "(xcodes' keychain layout may have changed; check `security find-generic-password -s $KEYCHAIN_SERVICE`.)" >&2
  exit 1
fi

# Round-trip through jq to validate the JSON shape AND minify
# (the 1Password field should be a single line for readability in
# the web UI).
if ! cookies_json=$(echo "$raw_session" | jq -c '.' 2>/dev/null); then
  echo "Error: keychain value isn't valid JSON. xcodes may have changed its session format." >&2
  echo "Raw value (first 200 chars):" >&2
  echo "$raw_session" | head -c 200 >&2
  exit 1
fi

# Verify the JSON is an object with at least one entry — otherwise
# the worker would no-op on every tick.
n=$(echo "$cookies_json" | jq 'if type == "object" then length else -1 end')
if [ "$n" -lt 1 ]; then
  echo "Error: keychain JSON has no cookie entries." >&2
  echo "$cookies_json" >&2
  exit 1
fi

echo "Captured $n cookie(s)."
echo "Writing to 1Password ($OP_VAULT / $OP_ITEM / $OP_FIELD)..."

# `op item edit` adds the field if it doesn't already exist;
# `concealed` marks it as a sensitive value so the 1P UI redacts
# it by default. Previous values stay in item history (1P keeps
# the last ~30 days), so a botched mint can be rolled back with
# `op item edit ... --revert`.
op item edit "$OP_ITEM" \
  --vault "$OP_VAULT" \
  "${OP_FIELD}[concealed]=$cookies_json"

echo
echo "Session refreshed. External Secrets will pick up the new value within ~5 min."
echo "Next steps:"
echo "  * Watch the worker's next tick (every 6h) in the server logs / Sentry."
echo "  * Or kick it now: ssh into the Tuist server pod and \`Tuist.XcodeMirror.Workers.ReconcileWorker.new(%{}) |> Oban.insert!\`."
