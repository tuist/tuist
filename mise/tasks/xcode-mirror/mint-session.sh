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
# 1P clicking, no extra package installs (`oras`, `jq`, `op` come
# from the root mise.toml).
#
# Apple auth: this script talks to `idmsa.apple.com` directly via
# curl — the same flow fastlane's spaceship and xcodes' AppleAPI
# implement under the hood. The trade-off is that if Apple changes
# their auth endpoints (rare but they do, every couple of years),
# we patch ~80 lines of explicit HTTP calls instead of waiting on a
# third-party release.
#
# Flow:
#   1. Ensure `op` is signed in.
#   2. Bootstrap 1P items if absent (one-time, on first run for a
#      given env's vault).
#   3. Do the Apple auth dance: signin → 2FA → trust.
#   4. Extract the cookies from the Netscape jar curl wrote.
#   5. Write the JSON cookie set straight into the 1P item.

set -euo pipefail

OP_VAULT="${usage_vault:-${TUIST_XCODE_MIRROR_OP_VAULT:-tuist-k8s-staging}}"
OP_ITEM="${TUIST_XCODE_MIRROR_OP_ITEM:-Tuist Xcode Mirror Session}"
OP_FIELD="${TUIST_XCODE_MIRROR_OP_FIELD:-session_cookies}"
OP_GHCR_ITEM="${TUIST_XCODE_MIRROR_OP_GHCR_ITEM:-GHCR_TUIST_BOT}"

# Tools (`oras`, `jq`, `op`, `curl`) come from the repo-root mise.toml.
# Running this task via `mise run xcode-mirror:mint-session` auto-installs
# what's missing — no brew dance here.

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

# === 3. Apple auth dance ====================================================

# Temp files for the curl cookie jar and HTTP response bodies. All
# cleaned up at exit — a captured session token leaking to disk
# is the worst-case here.
work_dir="$(mktemp -d -t xcode_mirror_mint.XXXXXX)"
cookie_jar="$work_dir/cookies"
trap 'rm -rf "$work_dir"' EXIT

# 4a. Widget key — the value Apple's web SSO uses to identify the
# requesting "service". App Store Connect publishes it through an
# unauthenticated config endpoint; same key works for the
# developer portal cookies we care about.
widget_key="$(
  curl -fsSL 'https://appstoreconnect.apple.com/olympus/v1/app/config?hostname=itunesconnect.apple.com' \
    | jq -r '.authServiceKey'
)"
if [ -z "$widget_key" ] || [ "$widget_key" = "null" ]; then
  echo "Error: couldn't fetch Apple's widget key from olympus/v1/app/config." >&2
  echo "(Apple may have moved the endpoint; check developer.apple.com/login)" >&2
  exit 1
fi

# 4b. Prompt for password. -s suppresses echo. We never persist
# this anywhere; it goes straight into the signin request and out
# of scope.
echo
echo "Signing in to developer.apple.com as $APPLE_ID..."
read -rsp "Apple ID password: " APPLE_PASSWORD
echo

# 4c. POST /signin. Apple returns 409 with `scnt` +
# `X-Apple-ID-Session-Id` response headers when 2FA is required
# (the common case for any account that's not exempted from
# Apple's MFA mandate, which is now everyone). 200 means the
# account skipped 2FA — vanishingly rare since 2019.
signin_body="$work_dir/signin.body"
signin_headers="$work_dir/signin.headers"
signin_status="$(
  curl -sS -o "$signin_body" -D "$signin_headers" \
    -w '%{http_code}' \
    -c "$cookie_jar" \
    -X POST \
    -H 'Accept: application/json, text/javascript' \
    -H 'Content-Type: application/json' \
    -H "X-Apple-Widget-Key: $widget_key" \
    -H 'X-Requested-With: XMLHttpRequest' \
    --data-binary "$(jq -nc --arg id "$APPLE_ID" --arg pw "$APPLE_PASSWORD" \
        '{accountName:$id, password:$pw, rememberMe:true}')" \
    'https://idmsa.apple.com/appleauth/auth/signin'
)"
unset APPLE_PASSWORD

case "$signin_status" in
  200)
    # No 2FA — already trusted IP / exempted. Cookies are in the
    # jar, skip to the dev-portal hop below.
    ;;
  409)
    # 2FA required. Apple's headers are case-preserved but case-
    # insensitive; grep -i is safe.
    scnt="$(grep -i '^scnt:' "$signin_headers" | tail -n1 | sed 's/^[Ss][Cc][Nn][Tt]: //' | tr -d '\r')"
    session_id="$(grep -i '^x-apple-id-session-id:' "$signin_headers" | tail -n1 | sed 's/^[Xx]-[Aa]pple-[Ii][Dd]-[Ss]ession-[Ii][Dd]: //' | tr -d '\r')"
    if [ -z "$scnt" ] || [ -z "$session_id" ]; then
      echo "Error: 409 from /signin but couldn't parse scnt / X-Apple-ID-Session-Id headers." >&2
      cat "$signin_headers" >&2
      exit 1
    fi

    # Trigger the trusted-device push so the user gets the prompt.
    curl -sS -o /dev/null -c "$cookie_jar" -b "$cookie_jar" \
      -X GET \
      -H 'Accept: application/json' \
      -H "X-Apple-Widget-Key: $widget_key" \
      -H "X-Apple-ID-Session-Id: $session_id" \
      -H "scnt: $scnt" \
      'https://idmsa.apple.com/appleauth/auth/verify/trusteddevice'

    echo "Approve the prompt on your trusted Apple device, then enter the 6-digit code."
    read -rp "2FA code: " CODE
    if [ -z "$CODE" ]; then
      echo "Error: empty 2FA code." >&2
      exit 1
    fi

    verify_status="$(
      curl -sS -o /dev/null -D "$work_dir/verify.headers" \
        -w '%{http_code}' \
        -c "$cookie_jar" -b "$cookie_jar" \
        -X POST \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        -H "X-Apple-Widget-Key: $widget_key" \
        -H "X-Apple-ID-Session-Id: $session_id" \
        -H "scnt: $scnt" \
        --data-binary "$(jq -nc --arg c "$CODE" '{securityCode:{code:$c}}')" \
        'https://idmsa.apple.com/appleauth/auth/verify/trusteddevice/securitycode'
    )"
    unset CODE

    if [ "$verify_status" != "204" ] && [ "$verify_status" != "200" ]; then
      echo "Error: 2FA verify returned HTTP $verify_status." >&2
      exit 1
    fi

    # Mark this signin as a "trusted" device so the session
    # outlasts the default few-hours window. Returns the bulk of
    # the session cookies we care about (myacinfo + dqsid).
    curl -sS -o /dev/null \
      -c "$cookie_jar" -b "$cookie_jar" \
      -X GET \
      -H 'Accept: application/json' \
      -H "X-Apple-Widget-Key: $widget_key" \
      -H "X-Apple-ID-Session-Id: $session_id" \
      -H "scnt: $scnt" \
      'https://idmsa.apple.com/appleauth/auth/2sv/trust'
    ;;
  *)
    echo "Error: /signin returned HTTP $signin_status." >&2
    echo "Response body:" >&2
    cat "$signin_body" >&2
    exit 1
    ;;
esac

# 4d. Hit developer.apple.com once to upgrade the cookie set into
# the form the dev-portal CDN accepts — Apple sets additional
# scoped cookies on the first authenticated request to that
# subdomain.
curl -sS -o /dev/null \
  -c "$cookie_jar" -b "$cookie_jar" \
  'https://developer.apple.com/account/' \
  >/dev/null 2>&1 || true

# === 4. Extract cookies as JSON =============================================

# Netscape cookie jar format:
#   <domain> <flag> <path> <secure> <expiry> <name> <value>
# Apple's flow drops cookies across multiple subdomains. We keep
# anything ending in `apple.com` so myacinfo (idmsa) + dqsid
# (developer.apple.com) + any cross-cutting auth crumbs all make
# it into the jar. The worker only reads the names it cares
# about; extras don't hurt.
cookies_json="$(
  awk -F'\t' -v OFS='' '
    BEGIN { print "{"; first = 1 }
    /^[^#]/ && NF == 7 {
      domain = $1; name = $6; value = $7
      sub(/^#HttpOnly_/, "", domain)
      if (domain !~ /apple\.com$/) next
      if (name == "") next
      if (!first) print ","
      # Escape inner quotes / backslashes so the JSON parses.
      gsub(/\\/, "\\\\", value)
      gsub(/"/, "\\\"", value)
      printf "\"%s\":\"%s\"", name, value
      first = 0
    }
    END { print "}" }
  ' "$cookie_jar"
)"

# Validate + minify with jq before pushing to 1P.
if ! echo "$cookies_json" | jq -e 'length > 0' >/dev/null 2>&1; then
  echo "Error: no apple.com cookies in the jar after the auth dance." >&2
  echo "Cookie jar dump:" >&2
  cat "$cookie_jar" >&2
  exit 1
fi
cookies_json="$(echo "$cookies_json" | jq -c '.')"
n="$(echo "$cookies_json" | jq 'length')"
echo "Captured $n cookie(s)."

# === 5. Write to 1Password =================================================

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
