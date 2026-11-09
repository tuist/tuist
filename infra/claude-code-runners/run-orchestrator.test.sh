#!/usr/bin/env bash
# Run inside the image. claude is stubbed; the actual supervisor is exercised.
set -euo pipefail
scratch=$(mktemp -d)
pid=''
cleanup_test() { [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; rm -rf "$scratch"; }
trap cleanup_test EXIT
mkdir -p "$scratch/bin" "$scratch/state" "$scratch/secrets"
export HOME="$scratch/state" PROVIDER_SECRET_DIR="$scratch/secrets"
export TUIST_URL=https://tuist.example.invalid TUIST_WORKLOAD_TOKEN_FILE="$scratch/identity"
printf 'fixture-workload' > "$TUIST_WORKLOAD_TOKEN_FILE"
printf 'fixture-environment-secret' > "$scratch/secrets/environment-secret"
export PATH="$scratch/bin:$PATH"
cat > "$scratch/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *"self-hosted-runner orchestrator --environment-secret-file "*"/environment-secret --hooks-dir /opt/tuist-claude-code/hooks"* ]]
[[ -z "${SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET:-}" && -z "${TUIST_TOKEN:-}" ]]
[[ "$TUIST_WORKLOAD_TOKEN_FILE" == */identity ]]
trap 'touch "$HOME/stopped"; exit 0' TERM
while true; do sleep 0.1; done
SH
chmod +x "$scratch/bin/claude"
export TUIST_TOKEN=must-not-inherit SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET=must-not-inherit
bash /tests/run-orchestrator.sh > "$scratch/output" 2>&1 & pid=$!
for _ in {1..100}; do [[ ! -f "$HOME/orchestrator-running" ]] || break; sleep 0.05; done
[[ -f "$HOME/orchestrator-running" ]]
kill -TERM "$pid"; wait "$pid"; pid=''
[[ -f "$HOME/stopped" && ! -f "$HOME/orchestrator-running" ]]
if grep -q 'fixture-' "$scratch/output"; then exit 1; fi
rm "$scratch/secrets/environment-secret"
if bash /tests/run-orchestrator.sh > "$scratch/output" 2>&1; then echo 'Missing environment secret unexpectedly accepted'; exit 1; fi
echo 'PASS: environment secret required, inherited credentials removed, shutdown cleans up, secrets absent from logs.'
