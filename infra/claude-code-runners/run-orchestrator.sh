#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${TUIST_URL:?Set the Tuist URL}"
: "${TUIST_WORKLOAD_TOKEN_FILE:?Mount the projected provider identity}"
[[ "$TUIST_URL" =~ ^https://[a-z0-9.-]+$ ]] || { echo 'TUIST_URL must be an HTTPS origin.' >&2; exit 1; }
[[ -s "$TUIST_WORKLOAD_TOKEN_FILE" ]] || { echo 'Provider identity is unavailable.' >&2; exit 1; }
secret_file=${PROVIDER_SECRET_DIR:-/secrets}/environment-secret
[[ -s "$secret_file" ]] || { echo 'Claude Code environment secret is empty.' >&2; exit 1; }
hooks_dir=${CLAUDE_CODE_HOOKS_DIR:-/opt/tuist-claude-code/hooks}
unset TUIST_TOKEN TUIST_ACCOUNT SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET
mkdir -p "${HOME:?}"
orchestrator_pid=''
# Invoked by traps, including termination while hooks run.
# shellcheck disable=SC2329
cleanup() {
  rm -f "$HOME/orchestrator-running"
  if [[ -n "$orchestrator_pid" ]]; then
    kill -TERM "$orchestrator_pid" 2>/dev/null || true
    wait "$orchestrator_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT
# The orchestrator log names sessions and accounts. Readiness means the
# orchestrator process is alive, not that Anthropic accepted the secret.
# A macOS sandbox can take minutes from a cold host, hence the long lease.
claude self-hosted-runner orchestrator \
  --environment-secret-file "$secret_file" \
  --hooks-dir "$hooks_dir" \
  --expected-spawn-seconds 300 \
  --hook-timeout 45 \
  --shutdown-drain-sec 60 \
  --health-port 0 >/dev/null 2>&1 &
orchestrator_pid=$!
touch "$HOME/orchestrator-running"
if wait "$orchestrator_pid"; then result=0; else result=$?; fi
echo "Claude Code orchestrator exited (status $result); restarting." >&2
exit "$result"
