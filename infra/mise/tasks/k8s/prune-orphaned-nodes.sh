#!/usr/bin/env bash
#MISE description="Identify and optionally delete stale Node objects with no live CAPI Machine backing"
#USAGE arg "<workload_kubeconfig>" help="Kubeconfig for the workload cluster that holds the Node objects"
#USAGE arg "<cluster_name>" help="Cluster API cluster name used to locate backing Machine objects"
#USAGE arg "[machines_kubeconfig]" help="Optional kubeconfig that holds the backing Machine objects. Defaults to the workload kubeconfig."

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: prune-orphaned-nodes.sh <workload_kubeconfig> <cluster_name> [machines_kubeconfig] [--apply] [--node-selector <selector>] [--name-prefix <prefix>] [--min-age-hours <hours>] [--max-print <count>]

Examples:
  mise run k8s:prune-orphaned-nodes ~/.kube/tuist-preview.yaml tuist-preview ~/.kube/tuist-mgmt.yaml
  mise run k8s:prune-orphaned-nodes ~/.kube/tuist-production.yaml tuist ~/.kube/tuist-production.yaml --name-prefix tuist-tuist-macos-fleet- --apply

Notes:
  - Dry-run by default. Pass --apply to delete the candidate Node objects.
  - When workload_kubeconfig and machines_kubeconfig are the same file, you
    must also pass --node-selector or --name-prefix. That guard prevents
    mixed clusters from treating unrelated nodes as orphaned.
EOF
  exit 64
}

if [ $# -lt 2 ]; then
  usage
fi

WORKLOAD_KUBECONFIG="$1"
CLUSTER_NAME="$2"
shift 2

MACHINES_KUBECONFIG="$WORKLOAD_KUBECONFIG"
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  MACHINES_KUBECONFIG="$1"
  shift
fi

APPLY=false
NODE_SELECTOR=""
NAME_PREFIX=""
MIN_AGE_HOURS=24
MAX_PRINT=200

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)
      APPLY=true
      shift
      ;;
    --node-selector)
      [ $# -ge 2 ] || usage
      NODE_SELECTOR="$2"
      shift 2
      ;;
    --name-prefix)
      [ $# -ge 2 ] || usage
      NAME_PREFIX="$2"
      shift 2
      ;;
    --min-age-hours)
      [ $# -ge 2 ] || usage
      MIN_AGE_HOURS="$2"
      shift 2
      ;;
    --max-print)
      [ $# -ge 2 ] || usage
      MAX_PRINT="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if ! [[ "$MIN_AGE_HOURS" =~ ^[0-9]+$ ]] || ! [[ "$MAX_PRINT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --min-age-hours and --max-print must be integers" >&2
  exit 64
fi

if [ "$WORKLOAD_KUBECONFIG" = "$MACHINES_KUBECONFIG" ] && [ -z "$NODE_SELECTOR" ] && [ -z "$NAME_PREFIX" ]; then
  echo "ERROR: same kubeconfig for nodes and machines requires --node-selector or --name-prefix" >&2
  exit 64
fi

command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found" >&2; exit 127; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 127; }

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

machines_json="$tmpdir/machines.json"
nodes_json="$tmpdir/nodes.json"
summary_json="$tmpdir/summary.json"

if ! KUBECONFIG="$MACHINES_KUBECONFIG" kubectl get machines.cluster.x-k8s.io -A \
  -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" -o json >"$machines_json"; then
  echo "ERROR: failed to read Machine objects for cluster $CLUSTER_NAME from $MACHINES_KUBECONFIG" >&2
  exit 1
fi

node_cmd=(kubectl get nodes -o json)
if [ -n "$NODE_SELECTOR" ]; then
  node_cmd+=( -l "$NODE_SELECTOR" )
fi

if ! KUBECONFIG="$WORKLOAD_KUBECONFIG" "${node_cmd[@]}" >"$nodes_json"; then
  echo "ERROR: failed to read Node objects from $WORKLOAD_KUBECONFIG" >&2
  exit 1
fi

MIN_AGE_SECONDS=$((MIN_AGE_HOURS * 3600))

jq -n \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg workload_kubeconfig "$WORKLOAD_KUBECONFIG" \
  --arg machines_kubeconfig "$MACHINES_KUBECONFIG" \
  --arg node_selector "$NODE_SELECTOR" \
  --arg name_prefix "$NAME_PREFIX" \
  --argjson min_age_seconds "$MIN_AGE_SECONDS" \
  --slurpfile machines "$machines_json" \
  --slurpfile nodes "$nodes_json" '
  ($machines[0].items // []) as $machine_items
  | ($machine_items | map(select(.metadata.deletionTimestamp == null) | .metadata.name)) as $live_machine_names
  | ($machine_items | map(select(.metadata.deletionTimestamp == null and .status.nodeRef.name? != null) | .status.nodeRef.name)) as $live_node_refs
  | ($machine_items | map(select(.metadata.deletionTimestamp != null) | .metadata.name)) as $deleting_machine_names
  | ($nodes[0].items // []) as $node_items
  | ($node_items
      | map(select(($name_prefix == "") or (.metadata.name | startswith($name_prefix))))
      | map(
          . as $node
          | (((.status.conditions // [])[]? | select(.type == "Ready") | .status) // "Unknown") as $ready
          | (now - (.metadata.creationTimestamp | fromdateiso8601)) as $age_seconds
          | {
              name: .metadata.name,
              ready: $ready,
              creationTimestamp: .metadata.creationTimestamp,
              ageHours: (($age_seconds / 3600) | floor),
              backing: (
                if ($deleting_machine_names | index($node.metadata.name)) != null then
                  "deleting-machine"
                else
                  "none"
                end
              ),
              candidate: (
                $ready != "True"
                and $age_seconds >= $min_age_seconds
                and ($live_machine_names | index($node.metadata.name)) == null
                and ($live_node_refs | index($node.metadata.name)) == null
              )
            }
        )
    ) as $evaluated_nodes
  | {
      clusterName: $cluster_name,
      workloadKubeconfig: $workload_kubeconfig,
      machinesKubeconfig: $machines_kubeconfig,
      nodeSelector: $node_selector,
      namePrefix: $name_prefix,
      minAgeHours: ($min_age_seconds / 3600),
      matchedNodes: ($evaluated_nodes | length),
      liveMachines: ($live_machine_names | length),
      liveNodeRefs: ($live_node_refs | length),
      deletingMachines: ($deleting_machine_names | length),
      candidates: ($evaluated_nodes | map(select(.candidate)) | sort_by(.ageHours, .name))
    }
' >"$summary_json"

echo "Cluster:            $(jq -r '.clusterName' "$summary_json")"
echo "Workload kubeconfig: $(jq -r '.workloadKubeconfig' "$summary_json")"
echo "Machines kubeconfig: $(jq -r '.machinesKubeconfig' "$summary_json")"
if [ -n "$NODE_SELECTOR" ]; then
  echo "Node selector:       $(jq -r '.nodeSelector' "$summary_json")"
fi
if [ -n "$NAME_PREFIX" ]; then
  echo "Name prefix:         $(jq -r '.namePrefix' "$summary_json")"
fi
echo "Min age hours:       $(jq -r '.minAgeHours' "$summary_json")"
echo "Matched nodes:       $(jq -r '.matchedNodes' "$summary_json")"
echo "Live machines:       $(jq -r '.liveMachines' "$summary_json")"
echo "Live nodeRefs:       $(jq -r '.liveNodeRefs' "$summary_json")"
echo "Deleting machines:   $(jq -r '.deletingMachines' "$summary_json")"
echo

candidate_count=$(jq -r '.candidates | length' "$summary_json")
if [ "$candidate_count" -eq 0 ]; then
  echo "No orphaned nodes matched the current filter."
  exit 0
fi

echo "Candidate nodes:     $candidate_count"
echo

printf '%-48s %-8s %-8s %-18s %s\n' "NAME" "READY" "AGE(h)" "BACKING" "CREATED"
jq -r --argjson max_print "$MAX_PRINT" '.candidates[:$max_print][] | [.name, .ready, (.ageHours | tostring), .backing, .creationTimestamp] | @tsv' "$summary_json" \
  | while IFS=$'\t' read -r name ready age_hours backing created; do
      printf '%-48s %-8s %-8s %-18s %s\n' "$name" "$ready" "$age_hours" "$backing" "$created"
    done
if [ "$candidate_count" -gt "$MAX_PRINT" ]; then
  echo "... $((candidate_count - MAX_PRINT)) more candidate node(s) omitted from the preview."
fi
echo

if [ "$APPLY" != true ]; then
  echo "Dry run only. Re-run with --apply to delete these Node objects."
  exit 0
fi

echo "Deleting $candidate_count orphaned Node object(s)..."
jq -r '.candidates[].name' "$summary_json" | while IFS= read -r node_name; do
  echo "  kubectl delete node $node_name"
  KUBECONFIG="$WORKLOAD_KUBECONFIG" kubectl delete node "$node_name" --wait=false
done

echo "Deleted $candidate_count Node object(s)."
