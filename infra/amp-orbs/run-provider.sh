#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${TUIST_URL:?Set the Tuist URL}"
: "${TUIST_WORKLOAD_TOKEN_FILE:?Mount the projected provider identity}"
[[ "$TUIST_URL" =~ ^https://[a-z0-9.-]+$ ]] || { echo 'TUIST_URL must be an HTTPS origin.' >&2; exit 1; }
[[ -s "$TUIST_WORKLOAD_TOKEN_FILE" ]] || { echo 'Provider identity is unavailable.' >&2; exit 1; }
secret_dir=${PROVIDER_SECRET_DIR:-/secrets}
export AMP_ORB_PROVIDER_TOKEN
AMP_ORB_PROVIDER_TOKEN=$(cat "$secret_dir/amp-token")
[[ -n "$AMP_ORB_PROVIDER_TOKEN" ]] || { echo 'Amp provider token is empty.' >&2; exit 1; }
unset TUIST_TOKEN TUIST_ACCOUNT
mkdir -p "${HOME:?}"
provider_pid=''
# Invoked by traps, including termination during a job.
# shellcheck disable=SC2329
cleanup() {
  rm -f "$HOME/provider-running"
  if [[ -n "$provider_pid" ]]; then
    kill -TERM "$provider_pid" 2>/dev/null || true
    wait "$provider_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT
# Amp/dispatch output can contain private thread data. Readiness means the
# consumer process is alive, not that Amp has authenticated its provider token.
amp orb provider /opt/tuist-amp-orbs/dispatch.sh >/dev/null 2>&1 &
provider_pid=$!
touch "$HOME/provider-running"
if wait "$provider_pid"; then result=0; else result=$?; fi
echo "Amp provider exited (status $result); restarting." >&2
exit "$result"
