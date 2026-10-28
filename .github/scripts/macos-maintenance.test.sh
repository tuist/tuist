#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export MAINTENANCE_TEST_FIXTURE="$work/machines.json" MAINTENANCE_TEST_CALLS="$work/calls"
cat > "$work/kubectl" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *' get scalewayapplesiliconmachines -o json' ]]; then
  cat "$MAINTENANCE_TEST_FIXTURE"
else
  printf '%s\n' "$*" >> "$MAINTENANCE_TEST_CALLS"
fi
MOCK
chmod +x "$work/kubectl"
export PATH="$work:$PATH"
cat > "$MAINTENANCE_TEST_FIXTURE" <<'JSON'
{"items":[{"metadata":{"name":"first"},"spec":{"fleetName":"processors"},"status":{}},{"metadata":{"name":"second"},"spec":{"fleetName":"processors"},"status":{}},{"metadata":{"name":"runner"},"spec":{"fleetName":"runners"},"status":{}}]}
JSON
run() { bash "$root/mise/tasks/macos-maintenance.sh" tuist-k8s-canary tuist processors "$@"; }
run 26.7.2 >/dev/null
[[ ! -e "$MAINTENANCE_TEST_CALLS" ]] || { echo 'plan wrote intent'; exit 1; }
run 26.7.2 --apply >/dev/null
[[ $(wc -l < "$MAINTENANCE_TEST_CALLS" | tr -d ' ') == 2 ]]
! grep -q runner "$MAINTENANCE_TEST_CALLS"
rm "$MAINTENANCE_TEST_CALLS"
if run '26.7;false' --apply >/dev/null 2>&1; then echo 'accepted invalid target'; exit 1; fi
jq '.items[0].status.osUpdate={phase:"Failed"}' "$MAINTENANCE_TEST_FIXTURE" > "$work/failed"
mv "$work/failed" "$MAINTENANCE_TEST_FIXTURE"
if run 26.7.2 --apply >/dev/null 2>&1; then echo 'overwrote failed maintenance'; exit 1; fi
[[ ! -e "$MAINTENANCE_TEST_CALLS" ]]
echo 'PASS: plan is read-only, apply selects only the requested fleet, invalid and failed waves are refused'
