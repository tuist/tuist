#!/usr/bin/env bash
# Test observer around the unchanged production dispatch adapter. Never log env.
# shellcheck disable=SC2016
set -euo pipefail
: "${TUIST_ORB_VALIDATION_DIR:?}"
directory=$(cd "$(dirname "$0")" && pwd)
"$directory/dispatch.sh"
[[ "$ORB_OPERATION" == spawn ]] || exit 0

sandbox=$(jq -er --arg orb "$ORB_ID" '.sandboxes[] | select(.amp_orb_id == $orb) | .id' "$TUIST_ORB_VALIDATION_DIR/state.json" 2>/dev/null || true)
# The observer can be one second behind the completed HTTP request.
for _ in {1..10}; do
  [[ -n "$sandbox" ]] && break
  sleep 1
  sandbox=$(jq -er --arg orb "$ORB_ID" '.sandboxes[] | select(.amp_orb_id == $orb) | .id' "$TUIST_ORB_VALIDATION_DIR/state.json" 2>/dev/null || true)
done
[[ "$sandbox" =~ ^[0-9a-f-]{36}$ ]]

command='set -euo pipefail
state=/workspace/amp/tuist-validation
if [[ ! -f $state/pid ]]; then
  mkdir -p "$state"
  cat > "$state/counter.sh" <<"COUNTER"
#!/bin/bash
count=0
while true; do count=$((count+1)); echo "$count" > /workspace/amp/tuist-validation/count; sleep 1; done
COUNTER
  nohup bash "$state/counter.sh" </dev/null >/dev/null 2>&1 &
  pid=$!
  echo "$pid" > "$state/pid"
  awk "{print \$22}" /proc/$pid/stat > "$state/start"
  chmod -R a+rwX "$state"
else
  pid=$(cat "$state/pid")
  [[ $(awk "{print \$22}" /proc/$pid/stat) == $(cat "$state/start") ]]
  before=$(cat "$state/count"); sleep 2
  [[ $(cat "$state/count") -gt $before ]]
fi
echo "Guest file and background process checks passed"'
request=$(mktemp "$TUIST_ORB_VALIDATION_DIR/exec.XXXXXX")
trap 'rm -f "$request"' EXIT
jq -nc --arg command "$command" '{command:$command,timeout_ms:15000}' > "$request"
response=$(jq -nr '"header = " + ("Authorization: Bearer " + env.TUIST_TOKEN | @json)' |
  curl --config - --silent --show-error --fail --max-time 30 \
    -H 'content-type: application/json' --data-binary "@$request" \
    "$TUIST_URL/api/accounts/$TUIST_ACCOUNT/sandboxes/$sandbox/exec")
jq -e '.exit_code == 0' <<< "$response" >/dev/null
jq -nc --arg orb "$ORB_ID" --arg sandbox "$sandbox" '{orb:$orb,sandbox:$sandbox}' >> "$TUIST_ORB_VALIDATION_DIR/spawns.jsonl"
echo 'Tuist dispatch and guest process check passed.'
