#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${TUIST_URL:?Set the Tuist URL}"
: "${TUIST_ACCOUNT:?Set the owning Tuist account}"
# Restrict the persisted credential filename and forbid sharing state across servers.
[[ "$TUIST_URL" =~ ^https://([a-z0-9.-]+)$ ]] || { echo 'TUIST_URL must be an HTTPS origin without a trailing slash.' >&2; exit 1; }
host=${BASH_REMATCH[1]}
secret_dir=${PROVIDER_SECRET_DIR:-/secrets}
state_dir=${HOME:?}
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$state_dir/config}
export TUIST_XDG_CONFIG_HOME="$XDG_CONFIG_HOME"
unset TUIST_TOKEN TUIST_CONFIG_TOKEN TUIST_CONFIG_CLOUD_TOKEN
mkdir -p "$XDG_CONFIG_HOME/tuist/credentials"
exec 9>"$state_dir/provider.lock"
flock -n 9 || { echo 'Another provider owns this credential volume.' >&2; exit 1; }
if [[ -f "$state_dir/origin" && $(cat "$state_dir/origin") != "$TUIST_URL/$TUIST_ACCOUNT" ]]; then
  echo 'This volume belongs to a different Tuist origin/account. Use a separate volume.' >&2
  exit 1
fi
rm -f "$state_dir/auth-ready"
printf '%s' "$TUIST_URL/$TUIST_ACCOUNT" > "$state_dir/origin"
credentials="$XDG_CONFIG_HOME/tuist/credentials/$host.json"
initial_secrets=$(sha256sum "$secret_dir/amp-token" "$secret_dir/tuist-credentials.json")
seed_hash=$(sha256sum "$secret_dir/tuist-credentials.json" | cut -d ' ' -f 1)
# Seed once, or when an operator deliberately supplies a NEW login. Never
# restore the original (spent) refresh token over a CLI-refreshed credential.
if [[ ! -f "$state_dir/seed.sha256" || $(cat "$state_dir/seed.sha256") != "$seed_hash" ]]; then
  jq -e '(.accessToken | type == "string" and length > 0) and
    (.refreshToken | type == "string" and length > 0) and (.rejected != true)' \
    "$secret_dir/tuist-credentials.json" >/dev/null
  install -m 600 "$secret_dir/tuist-credentials.json" "$credentials.new"
  mv "$credentials.new" "$credentials"
  printf '%s' "$seed_hash" > "$state_dir/seed.sha256"
fi
[[ -s "$credentials" ]] || { echo 'Persisted credentials are missing; provision a fresh login seed.' >&2; exit 1; }
export AMP_ORB_PROVIDER_TOKEN
AMP_ORB_PROVIDER_TOKEN=$(cat "$secret_dir/amp-token")
[[ -n "$AMP_ORB_PROVIDER_TOKEN" ]] || { echo 'Amp provider token is empty.' >&2; exit 1; }
provider_pid=''
# Invoked by the EXIT trap, including signal and authentication failure paths.
# shellcheck disable=SC2329
cleanup() {
  rm -f "$state_dir/auth-ready"
  if [[ -n "$provider_pid" ]]; then
    kill -TERM "$provider_pid" 2>/dev/null || true
    wait "$provider_pid" 2>/dev/null || true
  fi
}
trap 'cleanup' EXIT
trap 'exit 0' TERM INT
# Discard token output and private CLI diagnostics. Logs identify the failure,
# but must never become a second store for authentication material.
refresh_auth() {
  if ! timeout 45 tuist auth token --url "$TUIST_URL" 9>&- >/dev/null 2>&1; then
    echo 'Tuist authentication failed; check authorization or supply a fresh login seed.' >&2
    return 1
  fi
  touch "$state_dir/auth-ready"
}
refresh_auth
amp orb provider /opt/tuist-amp-orbs/dispatch.sh 9>&- >/dev/null 2>&1 &
provider_pid=$!
# Refresh even when Amp sends no work, keeping the rotating refresh session
# alive. Projected Secret updates trigger an orderly restart and reseed.
elapsed=0
while kill -0 "$provider_pid" 2>/dev/null; do
  sleep "${PROVIDER_POLL_SECONDS:-5}" 9>&- &
  wait $! || true
  if [[ $(sha256sum "$secret_dir/amp-token" "$secret_dir/tuist-credentials.json") != "$initial_secrets" ]]; then
    echo 'Provider credentials changed; restarting.'
    exit 0
  fi
  elapsed=$((elapsed + ${PROVIDER_POLL_SECONDS:-5}))
  if (( elapsed >= ${PROVIDER_REFRESH_SECONDS:-900} )); then
    refresh_auth
    elapsed=0
  fi
done
if wait "$provider_pid"; then provider_exit=0; else provider_exit=$?; fi
echo "Amp provider exited (status $provider_exit); the container will restart." >&2
exit "$provider_exit"
