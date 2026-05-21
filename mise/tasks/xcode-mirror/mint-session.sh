#!/usr/bin/env bash
#MISE description "Refresh the Apple session cookies used by the Tuist.XcodeMirror worker."
#USAGE arg "[apple_id]" help="Apple ID to sign in as (default: read from 1Password)."
#USAGE flag "--vault <vault>" help="1Password vault to write to (default: tuist-k8s-staging)."

# Quarterly maintenance for the Tuist.XcodeMirror worker. Apple's
# developer.apple.com session expires every ~30 days; when the
# worker hits a 401 it Sentry-emits `xcode_mirror.session_expired`
# with a link to this task.
#
# First run is also bootstrap: if `Tuist Xcode Mirror Session` or
# `GHCR_TUIST_BOT` items don't exist in the target vault yet, the
# task creates them (prompting for the GHCR PAT once) and then
# does its main job — populating the session cookies. No manual
# 1P clicking, no manual `brew install`.
#
# Flow:
#   1. Install missing prerequisites (`xcodes`, `oras`, `jq`,
#      `1password-cli`) via brew.
#   2. Ensure `op` is signed in.
#   3. Bootstrap 1P items if absent (one-time, on first run for a
#      given env's vault).
#   4. Spawn `xcodes signin <apple-id>` — interactive 2FA on a
#      trusted device. The session lands in your login keychain.
#   5. Read the just-stored session cookies out of the keychain.
#   6. Write them straight into the `Tuist Xcode Mirror Session`
#      item via `op item edit`. External Secrets propagates within
#      ~5 min; the next worker tick uses the fresh cookies.

set -euo pipefail

OP_VAULT="${usage_vault:-${TUIST_XCODE_MIRROR_OP_VAULT:-tuist-k8s-staging}}"
OP_ITEM="${TUIST_XCODE_MIRROR_OP_ITEM:-Tuist Xcode Mirror Session}"
OP_FIELD="${TUIST_XCODE_MIRROR_OP_FIELD:-session_cookies}"
OP_GHCR_ITEM="${TUIST_XCODE_MIRROR_OP_GHCR_ITEM:-GHCR_TUIST_BOT}"
KEYCHAIN_SERVICE="${TUIST_XCODE_MIRROR_KEYCHAIN_SERVICE:-xcodes}"

# === 1. Auto-install prerequisites ===========================================

# Map command names to brew formula / cask names. Most match
# 1:1; the 1Password CLI's command is `op` but the formula is
# `1password-cli`.
declare -a missing
declare -A brew_formula=(
  [xcodes]="xcodes"
  [oras]="oras"
  [jq]="jq"
  [op]="1password-cli"
)
for cmd in xcodes oras jq op; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("${brew_formula[$cmd]}")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Error: brew not installed. Install Homebrew first: https://brew.sh" >&2
    exit 1
  fi
  echo "Installing prerequisites: ${missing[*]}"
  brew install "${missing[@]}"
fi

# === 2. Ensure op is signed in ==============================================

if ! op whoami >/dev/null 2>&1; then
  # Try the desktop-app biometric integration first (silent if
  # configured, no-op otherwise). If that doesn't work, fall back
  # to interactive `op signin`.
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

# === 3. Bootstrap 1P items if absent ========================================

if ! op vault get "$OP_VAULT" >/dev/null 2>&1; then
  echo "Error: 1Password vault '$OP_VAULT' not visible to this account." >&2
  echo "(Use --vault <name> to target a different vault, or check your" >&2
  echo "1Password permissions for the env you're trying to set up.)" >&2
  exit 1
fi

# GHCR_TUIST_BOT item — the worker's push credential. One-time
# setup; the same PAT is used across envs (it's an org-level
# resource), but each env's vault holds its own copy because
# ESO's ClusterSecretStore scopes by vault.
if ! op item get "$OP_GHCR_ITEM" --vault "$OP_VAULT" >/dev/null 2>&1; then
  cat <<EOF

=== One-time setup: $OP_GHCR_ITEM (in $OP_VAULT) ===

The xcode-mirror worker pushes .xips to ghcr.io/tuist/xcode-xips
under the tuist-bot identity. Need a PAT with the \`write:packages\`
scope on the tuist org.

Mint one at https://github.com/settings/tokens (or reuse an
existing tuist-bot PAT that already has write:packages — same
token is fine across staging / canary / production).

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

# Resolve the Apple ID. Precedence:
#   1. CLI arg.
#   2. apple_id field of an existing session item.
#   3. Interactive prompt (and bootstrap the item if absent).
APPLE_ID="${usage_apple_id:-${1:-}}"
if [ -z "$APPLE_ID" ]; then
  APPLE_ID="$(op item get "$OP_ITEM" --vault "$OP_VAULT" --fields apple_id 2>/dev/null || true)"
fi
if [ -z "$APPLE_ID" ]; then
  echo
  read -rp "Apple ID for the xcode-mirror service account: " APPLE_ID
  if [ -z "$APPLE_ID" ]; then
    echo "Error: Apple ID required." >&2
    exit 1
  fi
fi

# Tuist Xcode Mirror Session item — created with a placeholder
# session_cookies field that the rest of the script overwrites
# with real cookies after `xcodes signin`. Splitting create vs.
# edit avoids needing a real cookie jar to bootstrap.
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

# === 4. Sign in to xcodes ===================================================

echo
echo "Signing in to xcodes as $APPLE_ID..."
echo "(2FA prompt → approve on your trusted Apple device → enter 6-digit code below.)"
echo

xcodes signin "$APPLE_ID"

# === 5. Read session cookies from keychain ===================================

echo
echo "Reading session cookies from keychain..."

raw_session=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$APPLE_ID" -w 2>/dev/null || true)

if [ -z "$raw_session" ]; then
  echo "Error: no '$KEYCHAIN_SERVICE' keychain entry for $APPLE_ID after signin." >&2
  echo "(xcodes' keychain layout may have changed; check \`security find-generic-password -s $KEYCHAIN_SERVICE\`.)" >&2
  exit 1
fi

if ! cookies_json=$(echo "$raw_session" | jq -c '.' 2>/dev/null); then
  echo "Error: keychain value isn't valid JSON. xcodes may have changed its session format." >&2
  echo "Raw value (first 200 chars):" >&2
  echo "$raw_session" | head -c 200 >&2
  exit 1
fi

n=$(echo "$cookies_json" | jq 'if type == "object" then length else -1 end')
if [ "$n" -lt 1 ]; then
  echo "Error: keychain JSON has no cookie entries." >&2
  echo "$cookies_json" >&2
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
