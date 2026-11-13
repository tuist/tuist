#!/usr/bin/env bash
# Test which macOS hosts a deploy waits on for the operator's tart-kubelet.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/tart-kubelet-rollout-gate.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin" "$scratch/logs"

new="$(printf 'b%.0s' {1..64})"
old="$(printf 'a%.0s' {1..64})"

cat > "$scratch/bin/kubectl" <<BASH
#!/usr/bin/env bash
args=" \$* "
case "\$args" in
  *" get pods "*) cat "$scratch/pods.json" ;;
  *" logs "*)
    for arg in "\$@"; do
      if [ -f "$scratch/logs/\$arg" ]; then cat "$scratch/logs/\$arg"; exit 0; fi
    done
    exit 1 ;;
  *" scalewayapplesiliconmachines "*) cat "$scratch/scaleway.json" ;;
  *" rackapplesiliconmachines "*) cat "$scratch/rack.json" ;;
  *" rackhostleases "*) cat "$scratch/leases.json" ;;
  *" nodes "*) cat "$scratch/nodes.json" ;;
  *) exit 1 ;;
esac
BASH
chmod +x "$scratch/bin/kubectl"

# Each argument is "<pod>:<sha|->[:terminating]"; "-" leaves the startup line
# out of the Pod's log, as after the log rotated.
operator() {
  local items=() pod sha terminating
  rm -f "$scratch/logs/"*
  for entry in "$@"; do
    IFS=: read -r pod sha terminating <<< "$entry"
    items+=("$(jq -cn --arg pod "$pod" --arg terminating "${terminating:-}" \
      '{metadata: ({name: $pod} + (if $terminating == "" then {} else {deletionTimestamp: "2026-11-13T09:00:00Z"} end)), status: {phase: "Running"}}')")
    {
      echo '{"level":"info","logger":"setup","msg":"starting manager"}'
      if [ "$sha" != - ]; then
        jq -cn --arg sha "$sha" '{level: "info", logger: "setup", msg: "loaded tart-kubelet binary", sha: $sha}'
      fi
      echo '{"level":"info","msg":"rolled new tart-kubelet","sha":"ignored"}'
    } > "$scratch/logs/$pod"
  done
  jq -cn '{items: $ARGS.positional | map(fromjson)}' --args ${items[@]+"${items[@]}"} > "$scratch/pods.json"
}

# Each argument is "<name>:<phase>:<sha>"; "-" is no SHA recorded yet.
machines() {
  local kind="$1" file="$2" items=() name phase sha
  shift 2
  for entry in "$@"; do
    IFS=: read -r name phase sha <<< "$entry"
    items+=("$(jq -cn --arg kind "$kind" --arg name "$name" --arg phase "$phase" --arg sha "$sha" \
      '{kind: $kind, metadata: {name: $name}, status: ({phase: $phase} + (if $sha == "-" then {} else {tartKubeletBinarySHA: $sha} end))}')")
  done
  jq -cn '{items: $ARGS.positional | map(fromjson)}' --args ${items[@]+"${items[@]}"} > "$scratch/$file"
}

# Each argument is "<name>:<state>:<node>:<sha>".
leases() {
  local items=() name state node sha
  for entry in "$@"; do
    IFS=: read -r name state node sha <<< "$entry"
    items+=("$(jq -cn --arg name "$name" --arg state "$state" --arg node "$node" --arg sha "$sha" \
      '{kind: "RackHostLease", metadata: {name: $name}, status: {state: $state, node: $node, tartKubeletBinarySHA: $sha}}')")
  done
  jq -cn '{items: $ARGS.positional | map(fromjson)}' --args ${items[@]+"${items[@]}"} > "$scratch/leases.json"
}

# Each argument is "<name>:<ready>:<unschedulable>".
nodes() {
  local items=() name ready unschedulable
  for entry in "$@"; do
    IFS=: read -r name ready unschedulable <<< "$entry"
    items+=("$(jq -cn --arg name "$name" --arg ready "$ready" --argjson unschedulable "$unschedulable" \
      '{metadata: {name: $name}, spec: {unschedulable: $unschedulable}, status: {conditions: [{type: "Ready", status: $ready}]}}')")
  done
  jq -cn '{items: $ARGS.positional | map(fromjson)}' --args ${items[@]+"${items[@]}"} > "$scratch/nodes.json"
}

# $1 expected exit code, $2 expected stdout, $3 description.
expect() {
  local actual status=0
  actual="$(PATH="$scratch/bin:$PATH" bash "$SCRIPT" tuist 2>/dev/null)" || status=$?
  if [ "$status" != "$1" ] || [ "$actual" != "$2" ]; then
    printf 'Expected exit %s and\n%s\nfor %s, got exit %s and\n%s\n' "$1" "$2" "$3" "$status" "$actual" >&2
    exit 1
  fi
}

# The fleet: two rented minis, three rack hosts and one borrowed host.
nodes \
  mini-1:True:false mini-2:True:false \
  rack-b01:True:false rack-b03:True:false rack-b04:True:true rack-b05:False:false \
  borrowed-b02:True:false
lent_and_unserving() {
  # b01 is lent to another env, whose operator pushes it (its Node here may
  # outlive the handover by a moment); b04 is cordoned,
  # b05 NotReady and b16 still bootstrapping, so none of them serves jobs.
  machines RackAppleSiliconMachine rack.json \
    "rack-b01:Lent:$old" "rack-b03:Ready:$1" "rack-b04:Ready:$old" \
    "rack-b05:Ready:$old" "rack-b16:Bootstrapping:-"
}
operator "op-1:$new" "op-2:$new" "op-0:$old:terminating"

machines ScalewayAppleSiliconMachine scaleway.json "mini-1:Ready:$new" "mini-2:Ready:$new"
lent_and_unserving "$new"
leases "b02:Active:borrowed-b02:$new" "b06:Returning:rack-b03:$old"
expect 0 "" "a fleet whose serving hosts all run the binary"

machines ScalewayAppleSiliconMachine scaleway.json "mini-1:Ready:$new" "mini-2:Ready:-"
lent_and_unserving "$old"
leases "b02:Active:borrowed-b02:$old" "b06:Returning:rack-b03:$old"
expect 1 "$(printf '%s\t%s\t%s\t%s\n' \
  ScalewayAppleSiliconMachine/mini-2 mini-2 none - \
  RackAppleSiliconMachine/rack-b03 rack-b03 "$old" - \
  RackHostLease/b02 borrowed-b02 "$old" -)" \
  "serving hosts on another binary or none yet"

operator "op-1:$new" "op-2:$old"
expect 1 "$(printf 'operator\t-\tmixed\tits Pods run different tart-kubelet binaries')" "an operator mid-rollout"

machines ScalewayAppleSiliconMachine scaleway.json "mini-1:Ready:$new" "mini-2:Ready:-"
lent_and_unserving "$new"
leases "b02:Active:borrowed-b02:$new"
operator "op-1:-" "op-2:$new"
expect 1 "$(printf '%s\t%s\t%s\t%s' ScalewayAppleSiliconMachine/mini-2 mini-2 none -)" \
  "an operator one of whose Pods has a rotated log"

operator "op-1:-" "op-2:-"
expect 0 "" "an operator this deploy did not start"

operator
expect 0 "" "an environment without the operator"

echo "tart-kubelet rollout gate tests passed."
