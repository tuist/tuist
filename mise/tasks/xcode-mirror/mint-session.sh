#!/usr/bin/env bash
#MISE description "Refresh the Apple session cookies used by the Tuist.XcodeMirror worker."
#USAGE arg "[apple_id]" help="Apple ID to sign in as (default: read from 1Password)."
#USAGE flag "--vault <vault>" help="1Password vault to write the session to (default: tuist-k8s-staging)."

# Quarterly maintenance for the Tuist.XcodeMirror worker. Apple's
# developer.apple.com session expires every ~30 days; when the
# worker hits a 401 it Sentry-emits `xcode_mirror.session_expired`
# with a link to this task.
#
# First run is also bootstrap: if `Tuist Xcode Mirror Session` or
# `GHCR_TUIST_BOT` items don't exist in the target vault yet, the
# task creates them (prompting for the GHCR PAT once) and then
# does its main job — populating the session cookies. No manual
# 1P clicking.
#
# Apple auth: delegated to `xcodes`. Apple switched
# `/appleauth/auth/signin` from plaintext-password POST to a
# Secure Remote Password (SRP) handshake — the client computes a
# proof derived from the password + a server-issued salt and
# never sends the password itself. Implementing SRP from scratch
# in bash is impractical (big-int math + SHA dance), so we let
# `xcodes` do it; its `AppleAPI` Swift dependency is SRP-aware
# and well-maintained. After xcodes auths, it persists the
# resulting cookie jar at
# `~/Library/Application Support/xcodes/session.json`, which we
# parse and copy into the 1P item.
#
# Flow:
#   1. Ensure `op` is signed in.
#   2. Bootstrap 1P items if absent (one-time, on first run for a
#      given env's vault).
#   3. Source the Apple ID password from the `Tuist Apple ID` 1P
#      item (override-able).
#   4. Clear any cached xcodes session, then trigger a fresh auth
#      by running an xcodes subcommand that requires login.
#      Operator types the 2FA code at the interactive prompt.
#   5. Read xcodes' persisted session, convert to `{name: value}`
#      JSON.
#   6. Write the JSON into the 1P item via `op item edit`.

set -euo pipefail

OP_VAULT="${usage_vault:-${TUIST_XCODE_MIRROR_OP_VAULT:-tuist-k8s-staging}}"
OP_ITEM="${TUIST_XCODE_MIRROR_OP_ITEM:-Tuist Xcode Mirror Session}"
OP_FIELD="${TUIST_XCODE_MIRROR_OP_FIELD:-session_cookies}"
OP_GHCR_ITEM="${TUIST_XCODE_MIRROR_OP_GHCR_ITEM:-GHCR_TUIST_BOT}"
# Where to source the Apple ID password from. The default points
# at the shared "Tuist Apple ID" login item in 1Password's
# Employee vault; teams using a different layout can override via
# env.
OP_APPLE_ITEM="${TUIST_XCODE_MIRROR_OP_APPLE_ITEM:-Tuist Apple ID}"
OP_APPLE_VAULT="${TUIST_XCODE_MIRROR_OP_APPLE_VAULT:-Employee}"
OP_APPLE_FIELD="${TUIST_XCODE_MIRROR_OP_APPLE_FIELD:-password}"

# === 1. Ensure op is signed in ==============================================

if ! op whoami >/dev/null 2>&1; then
  echo "1Password CLI not signed in. Trying interactive sign-in..."
  eval "$(op signin)" || true
fi

if ! op whoami >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Error: 1Password CLI still not signed in after attempting sign-in.

If you have the 1Password desktop app, enable the CLI integration:
  1Password → Settings → Developer → "Integrate with 1Password CLI".

Otherwise, sign in interactively:
  eval "$(op signin)"
EOF
  exit 1
fi

# === 2. Bootstrap 1P items if absent ========================================

if ! op vault get "$OP_VAULT" >/dev/null 2>&1; then
  echo "Error: 1Password vault '$OP_VAULT' not visible to this account." >&2
  echo "(Use --vault <name> to target a different vault.)" >&2
  exit 1
fi

if ! op item get "$OP_GHCR_ITEM" --vault "$OP_VAULT" >/dev/null 2>&1; then
  cat <<EOF

=== One-time setup: $OP_GHCR_ITEM (in $OP_VAULT) ===

The xcode-mirror worker pushes .xips to ghcr.io/tuist/xcode-xips
under the tuist-bot identity. Need a PAT with the \`write:packages\`
scope on the tuist org.

Mint one at https://github.com/settings/tokens (or reuse an
existing tuist-bot PAT — same token is fine across envs).

EOF
  read -rsp "Paste tuist-bot GHCR PAT (write:packages): " GHCR_TOKEN
  echo
  if [ -z "$GHCR_TOKEN" ]; then
    echo "Error: empty PAT." >&2
    exit 1
  fi
  op item create \
    --category="API Credential" \
    --vault="$OP_VAULT" \
    --title="$OP_GHCR_ITEM" \
    "username=tuist-bot" \
    "token[concealed]=$GHCR_TOKEN" \
    >/dev/null
  echo "Created $OP_VAULT / $OP_GHCR_ITEM."
  unset GHCR_TOKEN
fi

APPLE_ID="${usage_apple_id:-${1:-}}"
# Always prefer the authoritative source (the Tuist Apple ID login
# item). The session item also stores `apple_id` for convenience
# but it's category-coerced into a concealed field, so reading
# it without --reveal returns the `[use 'op ... --reveal']`
# placeholder. Avoid that whole class of bug by reading the
# username from the dedicated Apple ID item first.
if [ -z "$APPLE_ID" ]; then
  APPLE_ID="$(op item get "$OP_APPLE_ITEM" --vault "$OP_APPLE_VAULT" --fields username --reveal 2>/dev/null || true)"
fi
if [ -z "$APPLE_ID" ]; then
  APPLE_ID="$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields apple_id --reveal 2>/dev/null || true)"
fi
if [ -z "$APPLE_ID" ]; then
  echo
  read -rp "Apple ID for the xcode-mirror service account: " APPLE_ID
  if [ -z "$APPLE_ID" ]; then
    echo "Error: Apple ID required." >&2
    exit 1
  fi
fi

if ! op item get "$OP_ITEM" --vault "$OP_VAULT" >/dev/null 2>&1; then
  echo "Creating $OP_VAULT / $OP_ITEM (placeholder, will populate below)..."
  op item create \
    --category="API Credential" \
    --vault="$OP_VAULT" \
    --title="$OP_ITEM" \
    "apple_id=$APPLE_ID" \
    "${OP_FIELD}[concealed]={}" \
    >/dev/null
fi

# === 3. Source the Apple ID password from 1P =================================

# `--reveal` is the post-2.x op CLI flag for "give me the
# concealed value as a string"; without it `--fields password`
# returns the redacted placeholder.
APPLE_PASSWORD="$(
  op item get "$OP_APPLE_ITEM" --vault "$OP_APPLE_VAULT" \
    --fields "label=$OP_APPLE_FIELD" --reveal 2>/dev/null || true
)"

if [ -z "$APPLE_PASSWORD" ]; then
  echo
  echo "Couldn't read $OP_APPLE_VAULT/$OP_APPLE_ITEM/$OP_APPLE_FIELD from 1Password."
  echo "(Set TUIST_XCODE_MIRROR_OP_APPLE_{ITEM,VAULT,FIELD} to override paths,"
  echo " or paste the password below.)"
  read -rsp "Apple ID password for $APPLE_ID: " APPLE_PASSWORD
  echo
  if [ -z "$APPLE_PASSWORD" ]; then
    echo "Error: Apple ID password required." >&2
    exit 1
  fi
fi

# === 4. Trigger xcodes auth ==================================================

# Clear any cached session so we get fresh cookies. `xcodes
# signout` is safe to call even when no session exists.
xcodes signout >/dev/null 2>&1 || true

# Wipe any pre-existing session file too — xcodes only rewrites
# on successful auth, so a stale file would otherwise mask a
# failed auth from us.
SESSION_FILE="$HOME/Library/Application Support/xcodes/session.json"
rm -f "$SESSION_FILE"

# Trigger auth via `xcodes runtimes install <fake-name>`. xcodes
# only knows the catalog of installable runtimes after querying
# Apple's auth-walled developer-portal API, so the install command
# has to authenticate (SRP signin → 2FA push → 2FA code) before
# it can decide whether `<fake-name>` exists. By the time it bails
# out with "no such runtime", session.json has been persisted —
# which is the only thing we actually wanted.
#
# `xcodes runtimes downloadable` doesn't exist in xcodes 1.6.x
# (the runtimes subcommands are: installed | install | download |
# delete). `xcodes signin` was removed too. Using `install` with
# a sentinel name is the cleanest auth-only trigger.
#
# Credentials flow via env vars; xcodes reads `XCODES_USERNAME`
# and `XCODES_PASSWORD` (the per-command `--apple-id` flag doesn't
# exist on every subcommand). The 2FA prompt stays interactive —
# xcodes reads the 6-digit code from the terminal, the operator
# types it after approving the trusted-device push.
echo
echo "Signing in to developer.apple.com as $APPLE_ID via xcodes..."
echo "(Approve the prompt on your trusted Apple device, then enter the 6-digit code.)"
echo

# Sentinel runtime name. Apple's catalog never contains this, so
# xcodes always errors on the lookup *after* auth completes.
PROBE='__tuist_xcode_mirror_auth_probe__'

set +e
XCODES_USERNAME="$APPLE_ID" XCODES_PASSWORD="$APPLE_PASSWORD" \
  xcodes runtimes install "$PROBE" 2>&1 \
    | grep -viE "no (such|matching) runtime|Sorry, that runtime" \
    || true
set -e
unset APPLE_PASSWORD

if [ ! -f "$SESSION_FILE" ]; then
  echo "Error: xcodes didn't persist a session at $SESSION_FILE after auth." >&2
  echo "(If auth failed entirely, re-run for the error trace; if xcodes 1.6.x" >&2
  echo " changed the session-file path, check ~/Library/Application Support/" >&2
  echo " for the new location.)" >&2
  exit 1
fi

# === 5. Extract cookies as JSON ==============================================

# xcodes serialises its cookies as a JSON array of
# `HTTPCookieStorable` records:
#   [{"name": "myacinfo", "value": "DAW...", "domain": ".apple.com",
#     "path": "/", "expiresDate": ..., "secure": true, ...}, ...]
# We only want {name → value}.
cookies_json="$(jq -c 'map({(.name): .value}) | add // {}' "$SESSION_FILE")"

n="$(echo "$cookies_json" | jq 'length')"
if [ "$n" -lt 1 ]; then
  echo "Error: session file present but contained no cookies." >&2
  echo "Dump:" >&2
  cat "$SESSION_FILE" >&2
  exit 1
fi

echo "Captured $n cookie(s)."

# === 6. Write to 1Password ==================================================

echo "Writing to 1Password ($OP_VAULT / $OP_ITEM / $OP_FIELD)..."

op item edit "$OP_ITEM" \
  --vault "$OP_VAULT" \
  "${OP_FIELD}[concealed]=$cookies_json" \
  >/dev/null

echo
echo "Session refreshed. External Secrets propagates the new value within ~5 min."
echo "Next steps:"
echo "  * Watch the worker's next tick (every 6h) in server logs / Sentry."
echo "  * To kick the worker manually, see infra/macos-xcode-image/AGENTS.md."
