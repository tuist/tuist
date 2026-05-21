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
# Auth tool: `fastlane spaceauth`. Older versions of this script
# tried `xcodes signin` but xcodes only authenticates as part of
# a `download`/`install` operation — there's no standalone signin.
# Fastlane's spaceauth is the documented, decade-old tool for
# minting a developer.apple.com session that's portable to other
# clients (cookie replay), which is exactly what our Elixir worker
# does. The session cookies it emits include `myacinfo` (Apple's
# SSO cookie that covers developer-portal downloads) plus the
# `dqsid` session token.
#
# Flow:
#   1. Install missing prerequisites (`oras`, `jq`, `1password-cli`,
#      `fastlane`) via brew.
#   2. Ensure `op` is signed in.
#   3. Bootstrap 1P items if absent (one-time, on first run for a
#      given env's vault).
#   4. Run `fastlane spaceauth -u <apple-id>` — interactive 2FA
#      on a trusted device.
#   5. Parse Fastlane's YAML-encoded session into our `{name: value}`
#      JSON cookie jar.
#   6. Write it straight into the `Tuist Xcode Mirror Session`
#      item via `op item edit`. External Secrets propagates within
#      ~5 min; the next worker tick uses the fresh cookies.

set -euo pipefail

OP_VAULT="${usage_vault:-${TUIST_XCODE_MIRROR_OP_VAULT:-tuist-k8s-staging}}"
OP_ITEM="${TUIST_XCODE_MIRROR_OP_ITEM:-Tuist Xcode Mirror Session}"
OP_FIELD="${TUIST_XCODE_MIRROR_OP_FIELD:-session_cookies}"
OP_GHCR_ITEM="${TUIST_XCODE_MIRROR_OP_GHCR_ITEM:-GHCR_TUIST_BOT}"

# === 1. Auto-install prerequisites ===========================================

declare -a missing
declare -A brew_formula=(
  [oras]="oras"
  [jq]="jq"
  [op]="1password-cli"
  [fastlane]="fastlane"
)
for cmd in oras jq op fastlane; do
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
# after fastlane spaceauth succeeds. Splitting create vs. edit
# avoids needing a real cookie jar to bootstrap.
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

# === 4. Mint Apple session via fastlane spaceauth ============================

echo
echo "Signing in to developer.apple.com as $APPLE_ID via fastlane spaceauth..."
echo "(2FA prompt → approve on your trusted Apple device → enter 6-digit code below.)"
echo

# Capture fastlane's stdout/stderr to a temp file while still
# letting it interact with the TTY for password + 2FA prompts.
# `tee` keeps the user looking at progress; the temp file is what
# we parse afterwards. Trap-clean it on exit so a session token
# doesn't linger on disk.
tmp_output="$(mktemp -t fastlane_spaceauth.XXXXXX)"
trap 'rm -f "$tmp_output"' EXIT

if ! fastlane spaceauth -u "$APPLE_ID" 2>&1 | tee "$tmp_output"; then
  echo "Error: fastlane spaceauth failed. See output above." >&2
  exit 1
fi

# === 5. Parse Fastlane's YAML session into our JSON cookie jar ==============

# fastlane spaceauth prints something like:
#
#   Pass the following via the FASTLANE_SESSION environment variable:
#   ---
#   - !ruby/object:HTTP::Cookie
#     name: myacinfo
#     value: DAW...
#     ...
#   Example:
#   export FASTLANE_SESSION='---\n- !ruby/object:...'
#
# We grab the `export FASTLANE_SESSION='...'` line — single-line,
# easier to parse than the multi-line YAML block above.
session_line="$(grep -E "^export FASTLANE_SESSION=" "$tmp_output" | head -n1 || true)"
if [ -z "$session_line" ]; then
  echo "Error: fastlane spaceauth didn't produce a FASTLANE_SESSION line." >&2
  echo "(Check the output above for what went wrong.)" >&2
  exit 1
fi

# Strip the `export FASTLANE_SESSION='` prefix and the trailing `'`.
session_yaml="${session_line#export FASTLANE_SESSION=\'}"
session_yaml="${session_yaml%\'}"

# Convert the Ruby-flavoured YAML to our {name: value} JSON. Pass
# the YAML via stdin to dodge the bash single-quote escaping
# fastlane uses in its `export` line (`'\''` → `'`); Ruby's `gets`
# preserves whatever fastlane wrote literally. `unsafe_load` is
# needed to deserialise the `!ruby/object:HTTP::Cookie` tagged
# values — they're trusted (we just minted them).
cookies_json="$(printf '%s' "$session_yaml" | ruby -ryaml -rjson -e '
  yaml = STDIN.read
  cookies = YAML.unsafe_load(yaml)
  result = cookies.each_with_object({}) do |c, acc|
    name = c.respond_to?(:name) ? c.name : c["name"]
    value = c.respond_to?(:value) ? c.value : c["value"]
    acc[name] = value if name && value
  end
  raise "no cookies extracted from fastlane session" if result.empty?
  puts result.to_json
')"

if [ -z "$cookies_json" ]; then
  echo "Error: failed to extract cookies from fastlane session." >&2
  exit 1
fi

n="$(echo "$cookies_json" | jq 'length')"
echo "Captured $n cookie(s)."

# === 6. Write to 1Password =================================================

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
