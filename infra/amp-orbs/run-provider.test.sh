#!/usr/bin/env bash
# Execute inside the Linux provider image; only Amp/Tuist network clients are stubbed.
set -euo pipefail
scratch=$(mktemp -d)
pid=''
cleanup_test() {
  local test_exit=$?
  if [[ "$test_exit" != 0 ]]; then cat "$scratch/output" 2>/dev/null || true; fi
  [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup_test EXIT
mkdir -p "$scratch/bin" "$scratch/state" "$scratch/secrets"
export HOME="$scratch/state" XDG_CONFIG_HOME="$scratch/state/config" PROVIDER_SECRET_DIR="$scratch/secrets"
export TUIST_URL=https://tuist.example.invalid TUIST_ACCOUNT=tuist
export PROVIDER_POLL_SECONDS=1 PROVIDER_REFRESH_SECONDS=2
export CALLS="$scratch/calls"
export PATH="$scratch/bin:$PATH"
cat > "$scratch/bin/tuist" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'auth token --url https://tuist.example.invalid' ]]
printf 'refresh\n' >> "$CALLS"
[[ ! -f "$HOME/fail-auth" ]] || exit 1
# Model refresh rotation in the CLI's actual credential path.
jq '.refreshToken = "rotated-token"' "$XDG_CONFIG_HOME/tuist/credentials/tuist.example.invalid.json" > "$HOME/new.json"
mv "$HOME/new.json" "$XDG_CONFIG_HOME/tuist/credentials/tuist.example.invalid.json"
echo private-access-token
SH
cat > "$scratch/bin/amp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$AMP_ORB_PROVIDER_TOKEN" == amp-secret* ]]
[[ ! -f "$HOME/exit-amp" ]] || exit 17
printf 'start\n' >> "$CALLS"
trap 'printf "stop\n" >> "$CALLS"; exit 0' TERM
# These must not reach cluster logs.
echo private-amp-log
while true; do sleep 0.2 & wait $! || true; done
SH
chmod +x "$scratch/bin/amp" "$scratch/bin/tuist"
echo amp-secret > "$PROVIDER_SECRET_DIR/amp-token"
echo '{"accessToken":"access","refreshToken":"initial"}' > "$PROVIDER_SECRET_DIR/tuist-credentials.json"
wait_for() {
  for ((i=0; i<100; i++)); do
    if "$@"; then return 0; fi
    sleep 0.1
  done
  echo 'Timed out waiting for runtime assertion' >&2
  exit 1
}
script=/opt/tuist-amp-orbs/run-provider.sh
bash "$script" > "$scratch/output" 2>&1 & pid=$!
wait_for test -f "$HOME/auth-ready"
wait_for grep -q start "$CALLS"
# A second process sharing the PVC cannot consume Amp jobs or refresh credentials.
if bash "$script" > "$scratch/second-output" 2>&1; then echo 'Accepted duplicate provider' >&2; exit 1; fi
grep -q 'Another provider' "$scratch/second-output"
# shellcheck disable=SC2016
wait_for bash -c '[[ $(grep -c refresh "$CALLS") -ge 2 ]]'
# Updating a mounted Secret stops the old consumer before Kubernetes restarts it.
echo amp-secret-rotated > "$PROVIDER_SECRET_DIR/amp-token"
wait "$pid"; pid=''
grep -q stop "$CALLS"
test ! -f "$HOME/auth-ready"
if grep -Eq 'private-access-token|private-amp-log|amp-secret' "$scratch/output"; then exit 1; fi
# Simulate an already rotated credential: unchanged seed must not replace it.
echo '{"accessToken":"preserved","refreshToken":"rotated-token"}' > "$XDG_CONFIG_HOME/tuist/credentials/tuist.example.invalid.json"
cat > "$scratch/bin/tuist" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
jq -e '.accessToken == "preserved"' "$XDG_CONFIG_HOME/tuist/credentials/tuist.example.invalid.json" >/dev/null
[[ ! -f "$HOME/fail-auth" ]]
echo private-access-token
SH
bash "$script" >> "$scratch/output" 2>&1 & pid=$!
wait_for test -f "$HOME/auth-ready"
kill -TERM "$pid"; wait "$pid"; pid=''
test ! -f "$HOME/auth-ready"
# Authentication rejection does not start a consumer or leave a ready marker.
touch "$HOME/fail-auth"
if bash "$script" >> "$scratch/output" 2>&1; then echo 'Accepted rejected auth' >&2; exit 1; fi
test ! -f "$HOME/auth-ready"
# State must never migrate silently between environments or account owners.
if TUIST_ACCOUNT=other bash "$script" >> "$scratch/output" 2>&1; then echo 'Reused another account state' >&2; exit 1; fi
# A fresh operator seed is accepted, replacing the spent session deliberately.
rm "$HOME/fail-auth"
echo '{"accessToken":"preserved","refreshToken":"new-login"}' > "$PROVIDER_SECRET_DIR/tuist-credentials.json"
bash "$script" >> "$scratch/output" 2>&1 & pid=$!
wait_for test -f "$HOME/auth-ready"
jq -e '.refreshToken == "new-login"' "$XDG_CONFIG_HOME/tuist/credentials/tuist.example.invalid.json" >/dev/null
kill -TERM "$pid"; wait "$pid"; pid=''
# A dead consumer exits the container so Kubernetes restarts it.
touch "$HOME/exit-amp"
if bash "$script" >> "$scratch/output" 2>&1; then
  echo 'Accepted dead Amp process' >&2; exit 1
else
  test "$?" = 17
fi
test ! -f "$HOME/auth-ready"
echo 'PASS: auth refresh, persistent rotation, singleton lock, secret reload, shutdown and failure handling'
