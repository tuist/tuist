#!/usr/bin/env bash
# Run inside the Linux image. Amp is stubbed; the actual supervisor is exercised.
set -euo pipefail
scratch=$(mktemp -d)
pid=''
cleanup_test() { [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; rm -rf "$scratch"; }
trap cleanup_test EXIT
mkdir -p "$scratch/bin" "$scratch/state" "$scratch/secrets"
export HOME="$scratch/state" PROVIDER_SECRET_DIR="$scratch/secrets"
export TUIST_URL=https://tuist.example.invalid TUIST_WORKLOAD_TOKEN_FILE="$scratch/identity"
printf 'fixture-workload' > "$TUIST_WORKLOAD_TOKEN_FILE"
printf 'fixture-amp-token' > "$scratch/secrets/amp-token"
export PATH="$scratch/bin:$PATH"
cat > "$scratch/bin/amp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$AMP_ORB_PROVIDER_TOKEN" == fixture-amp-token ]]
[[ "$TUIST_WORKLOAD_TOKEN_FILE" == */identity ]]
[[ -z "${TUIST_ACCOUNT:-}" && -z "${TUIST_TOKEN:-}" ]]
trap 'touch "$HOME/stopped"; exit 0' TERM
while true; do sleep 0.1; done
SH
chmod +x "$scratch/bin/amp"
export TUIST_TOKEN=must-not-inherit TUIST_ACCOUNT=must-not-inherit
bash /tests/run-provider.sh > "$scratch/output" 2>&1 & pid=$!
for _ in {1..100}; do [[ ! -f "$HOME/provider-running" ]] || break; sleep 0.05; done
[[ -f "$HOME/provider-running" ]]
kill -TERM "$pid"; wait "$pid"; pid=''
[[ -f "$HOME/stopped" && ! -f "$HOME/provider-running" ]]
if grep -q 'fixture-' "$scratch/output"; then exit 1; fi
rm "$TUIST_WORKLOAD_TOKEN_FILE"
if bash /tests/run-provider.sh > "$scratch/output" 2>&1; then echo 'Missing identity unexpectedly accepted'; exit 1; fi
echo 'PASS: workload identity required, inherited user credentials removed, shutdown cleans up, secrets absent from logs.'
