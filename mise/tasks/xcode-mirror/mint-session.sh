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

# We don't know xcodes' exact session-file path across versions
# (1.6 used `~/Library/Application Support/xcodes/session.json`;
# the underlying AppleAPI Swift package has changed file names
# more than once). Instead of guessing, baseline the filesystem,
# run xcodes, and detect whichever file appeared.
MARKER="$(mktemp -t xcode_mirror_marker.XXXXXX)"
# Bump the mtime by a second so filesystem 1s granularity doesn't
# match the marker against the same-second creation of the
# session file.
sleep 1

# xcodes' runtime + Xcode catalog lookups are local (cached from
# xcodereleases.com), so passing a fake version/runtime name
# short-circuits before auth. The only reliable auth trigger is
# `xcodes install <real-version>` — it auths, persists the
# session, then starts the actual .xip download. We watch for the
# session file appearing and SIGINT xcodes before the download
# eats any meaningful bandwidth.
#
# Pick a real version from xcodes' own catalog so we don't drift
# against Apple's release pace. The choice doesn't matter — any
# installable version triggers the same auth path.
XCODE_VERSION_FOR_AUTH="${TUIST_XCODE_MIRROR_PROBE_VERSION:-$(xcodes list 2>/dev/null | grep -vi '(Installed' | tail -n1 | awk '{print $1}')}"
if [ -z "$XCODE_VERSION_FOR_AUTH" ]; then
  XCODE_VERSION_FOR_AUTH="26.4.1"
fi

JUNK_DIR="$(mktemp -d -t xcode_mirror_junk.XXXXXX)"
SESSION_FILE=""

# Watcher: scan for any newly-created file in xcodes' likely data
# directories. When one appears that looks like a JSON cookie jar,
# SIGINT xcodes so the .xip download aborts. Polls every 0.5 s for
# up to 5 min (well past any realistic 2FA flow).
(
  for _ in $(seq 1 600); do
    sleep 0.5
    found="$(
      find "$HOME/Library/Application Support" "$HOME/Library/Caches" \
        -maxdepth 4 -newer "$MARKER" -type f -name '*.json' 2>/dev/null \
        | head -n1
    )"
    if [ -n "$found" ]; then
      # Brief delay so xcodes can finish fsyncing + chmod'ing the
      # file before we yank the rug. 1s is plenty.
      sleep 1
      # SIGINT — gracefully aborts the download. xcodes prints a
      # "Cancelled" line and exits non-zero, both of which we
      # ignore.
      pkill -INT -x xcodes 2>/dev/null || true
      break
    fi
  done
) &
WATCHER_PID=$!
trap 'kill $WATCHER_PID 2>/dev/null || true; rm -rf "$JUNK_DIR" "$MARKER"' EXIT

echo
echo "Signing in to developer.apple.com as $APPLE_ID via xcodes..."
echo "(Triggering auth via 'xcodes install $XCODE_VERSION_FOR_AUTH'."
echo " Approve the prompt on your trusted Apple device, then enter the 6-digit code."
echo " We'll abort the download as soon as the session is captured.)"
echo

set +e
XCODES_USERNAME="$APPLE_ID" XCODES_PASSWORD="$APPLE_PASSWORD" \
  xcodes install "$XCODE_VERSION_FOR_AUTH" --directory "$JUNK_DIR"
set -e
unset APPLE_PASSWORD

# Locate the file the watcher saw (or scan again, in case the
# watcher missed it on a slow disk).
SESSION_FILE="$(
  find "$HOME/Library/Application Support" "$HOME/Library/Caches" \
    -maxdepth 4 -newer "$MARKER" -type f -name '*.json' 2>/dev/null \
    | head -n1
)"

if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  echo "Error: xcodes didn't persist a session JSON anywhere we could find." >&2
  echo "(Sanity-check: anything new in ~/Library?)" >&2
  find "$HOME/Library/Application Support" "$HOME/Library/Caches" \
    -maxdepth 4 -newer "$MARKER" -type f 2>/dev/null >&2 || true
  exit 1
fi

echo "Found xcodes session at: $SESSION_FILE"

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
