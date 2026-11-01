#!/usr/bin/env bash
#MISE description="Capture bounded private connectivity evidence using view access only"
set +x
set -euo pipefail
umask 077

# timeout must supervise the whole process group, including a credential plugin
# that hangs before kubectl's request timeout begins. No credential fallback.
timeout_bin=$(command -v timeout || command -v gtimeout) || {
  echo "Install coreutils (timeout), jq and kubectl before capture." >&2
  exit 2
}
if [[ ${1:-} != --bounded ]]; then
  exec "$timeout_bin" --kill-after=3s 120s bash "$0" --bounded "$@"
fi
shift
if [[ $# -lt 5 || $# -gt 8 ]]; then
  echo "Usage: capture-connectivity.sh CONTEXT NAMESPACE SINCE_UTC PRIVATE_PARENT POD [POD ...] (1-4 pods)" >&2
  exit 2
fi
context=$1 namespace=$2 since=$3 parent=$4
shift 4
case "$context" in tuist-k8s-staging|tuist-k8s-canary|tuist-k8s-production) ;; *) exit 2 ;; esac
[[ "$namespace" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#namespace} -le 63 ]] || exit 2
[[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || exit 2
for pod in "$@"; do
  [[ "$pod" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ && ${#pod} -le 253 ]] || exit 2
done
command -v jq >/dev/null
command -v kubectl >/dev/null
[[ -d "$parent" ]] || exit 2
out=$(mktemp -d "$parent/connectivity-capture.XXXXXXXX")
touch "$out/INCOMPLETE"
echo "Private capture directory: $out"
jq -nc --arg since "$since" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{since_utc:$since,collected_at_utc:$at,private:true,log_tail:2000,log_bytes:262144,wall_seconds:120}' > "$out/window.json"
failed=0

# Persist projections only. Raw API objects, logs and errors never reach disk.
# Cap each input at 1 MiB. A capped/failed pipeline is not successful evidence.
capture() {
  local name=$1 filter=$2
  shift 2
  if "$timeout_bin" --kill-after=2s 12s kubectl --context "$context" --request-timeout=8s "$@" 2>/dev/null \
    | head -c 1048577 | jq -Rsc "if utf8bytelength > 1048576 then error(\"size limit\") else fromjson | $filter end" > "$out/$name.tmp" 2>/dev/null; then
    if [[ $(wc -c < "$out/$name.tmp") -le 1048576 ]]; then
      mv "$out/$name.tmp" "$out/$name.json"
      return
    fi
  fi
  rm -f "$out/$name.tmp"
  printf '%s\n' "$name: unavailable (request, parsing or size limit)" >> "$out/unavailable.txt"
  failed=1
}

# These are jq variables, not shell expansions.
# shellcheck disable=SC2016
log_filter='
  def number: if type == "number" and . >= 0 and . <= 1e16 then . else null end;
  capture("^(?<at>[^ ]+) (?<record>.*)$")
  | select(.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$"))
  | . as $line | (try (.record | fromjson) catch {}) as $json
  | ($json.fields // $json) as $r
  | if $r["event.name"] == "kura.connectivity.sample" then
      select(($r.target // "") | test("^(tuist-tuist-server\\.(tuist|tuist-staging|tuist-canary)|k8s-monitoring-alloy-receiver\\.observability)\\.svc\\.cluster\\.local\\.?$"))
      | select(["ok","dns_error","address_error","connect_error","http_error","request_error","informational_response"] | index($r.outcome))
      | {at:$line.at,event:"sample",target:$r.target,outcome:$r.outcome,
         port:($r.port|number),status:($r.status|number),
         started_at_unix_ms:($r.started_at_unix_ms|number),connect_budget_ms:($r.connect_budget_ms|number),
         dns_ms:($r.dns_ms|number),connect_ms:($r.connect_ms|number),
         first_byte_ms:($r.first_byte_ms|number),headers_ms:($r.headers_ms|number),total_ms:($r.total_ms|number)}
    elif $r["event.name"] == "kura.telemetry.http_export_failed" then
      select(["timeout","http_status","tls","dns","connect","body","other"] | index($r["error.type"]))
      | {at:$line.at,event:"http_export_failed",category:$r["error.type"],
         duration_ms:($r["kura.telemetry.export.duration_ms"]|number),
         suppressed:($r["kura.log.suppressed_count"]|number)}
    else empty end'

logs() {
  local name=$1 mode=$2
  shift 2
  local filter=$log_filter
  if [[ "$mode" == cilium ]]; then
    filter='capture("^(?<at>[^ ]+) (?<record>.*)$")
      | select(.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$"))
      | select(.record | test("(?i)(api-server|apiserver|kubernetes|k8s)"))
      | select(.record | test("(?i)(i/o timeout|context deadline exceeded|connection timed out)"))
      | {at,event:"cilium_api_timeout"}'
  fi
  if "$timeout_bin" --kill-after=2s 12s kubectl --context "$context" --request-timeout=8s "$@" \
    --since-time="$since" --timestamps=true --tail=2000 --limit-bytes=262144 2>/dev/null \
    | head -c 262145 | jq -Rsc "if utf8bytelength > 262144 then error(\"size limit\") else split(\"\\n\")[] | $filter end" > "$out/$name.tmp" 2>/dev/null; then
    if [[ $(wc -c < "$out/$name.tmp") -le 1048576 ]]; then
      mv "$out/$name.tmp" "$out/$name.jsonl"
      return
    fi
  fi
  rm -f "$out/$name.tmp"
  printf '%s\n' "$name: unavailable (request, parsing or size limit)" >> "$out/unavailable.txt"
  failed=1
}

i=0
for pod in "$@"; do
  i=$((i + 1))
  capture "pod-$i" '{name:.metadata.name,namespace:.metadata.namespace,uid:.metadata.uid,
    node:.spec.nodeName,owner:([.metadata.ownerReferences[]? | select(.controller == true and .kind == "StatefulSet") | .name][0]),
    phase:.status.phase,ready:([.status.conditions[]? | select(.type == "Ready") | .status][0]),
    containers:[.status.containerStatuses[]? | {name,imageID,restartCount,ready}]}' \
    -n "$namespace" get pod "$pod" -o json
  logs "pod-$i-logs" kura -n "$namespace" logs "$pod" -c kura
  [[ -f "$out/pod-$i.json" ]] || continue
  node=$(jq -r '.node // empty' "$out/pod-$i.json")
  owner=$(jq -r '.owner // empty' "$out/pod-$i.json")
  if [[ -n "$owner" ]]; then
    capture "rollout-$i" '{name:.metadata.name,generation:.metadata.generation,
      observedGeneration:.status.observedGeneration,replicas:.status.replicas,
      readyReplicas:.status.readyReplicas,currentRevision:.status.currentRevision,updateRevision:.status.updateRevision}' \
      -n "$namespace" get statefulset "$owner" -o json
  fi
  if [[ -z "$node" || -z "$owner" ]]; then
    printf '%s\n' "pod-$i: placement or StatefulSet owner unavailable" >> "$out/unavailable.txt"
    failed=1
  fi
  [[ -n "$node" ]] || continue
  capture "node-$i" '{name:.metadata.name,uid:.metadata.uid,
    conditions:[.status.conditions[]? | {type,status,lastTransitionTime}]}' get node "$node" -o json
  capture "cilium-$i" '{count:(.items|length),pods:[.items[:2][] | {name:.metadata.name,namespace:.metadata.namespace,uid:.metadata.uid}]}' \
    -n kube-system get pods -l k8s-app=cilium --field-selector "spec.nodeName=$node" -o json
  [[ -f "$out/cilium-$i.json" ]] || continue
  if [[ $(jq -r '.count' "$out/cilium-$i.json") != 1 ]]; then
    printf '%s\n' "cilium-$i: missing or ambiguous same-node agent" >> "$out/unavailable.txt"
    failed=1
    continue
  fi
  agent=$(jq -r '.pods[0].name // empty' "$out/cilium-$i.json")
  if [[ -n "$agent" ]]; then
    logs "cilium-$i-logs" cilium -n kube-system logs "$agent" -c cilium-agent
  fi
done
if [[ "$failed" == 0 ]]; then
  rm "$out/INCOMPLETE"
else
  echo "Capture incomplete; see unavailable.txt. Do not interpret missing records as healthy." >&2
  exit 1
fi
