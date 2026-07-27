#!/usr/bin/env bash
#MISE description="Safely replace one production Linux runner node and verify its reserved memory headroom."
#USAGE arg "<node>" help="Exact production workload node name"
#USAGE arg "<confirmation>" help="Repeat the exact node name to confirm"

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <node> <confirmation>" >&2
  exit 64
fi

target_node="$1"
confirmation="$2"
management_namespace="${MANAGEMENT_NAMESPACE:-org-tuist}"
runner_namespace="${RUNNER_NAMESPACE:-tuist-runners}"
cluster_name="tuist"
management_kubeconfig="${KUBECONFIG:?KUBECONFIG must point at the management cluster}"

if [ "$confirmation" != "$target_node" ]; then
  echo "ERROR: confirmation must exactly match the target node" >&2
  exit 64
fi

case "$target_node" in
  bm-tuist-runners-linux-*) ;;
  *)
    echo "ERROR: target must be a production runners-linux node" >&2
    exit 64
    ;;
esac

for command in base64 jq kubectl; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: $command is required" >&2
    exit 69
  fi
done

rotation_directory="$(mktemp -d)"
workload_kubeconfig="$rotation_directory/workload-kubeconfig"
cordoned_by_script=false
replacement_started=false

management_kubectl() {
  kubectl --kubeconfig "$management_kubeconfig" "$@"
}

workload_kubectl() {
  kubectl --kubeconfig "$workload_kubeconfig" "$@"
}

cleanup() {
  local exit_status=$?

  if [ "$exit_status" -ne 0 ] &&
    [ "$cordoned_by_script" = "true" ] &&
    [ "$replacement_started" = "false" ]; then
    echo "Rotation stopped before replacement; restoring scheduling on $target_node" >&2
    workload_kubectl uncordon "$target_node" >/dev/null 2>&1 || true
  fi

  rm -f "$workload_kubeconfig"
  rmdir "$rotation_directory" 2>/dev/null || true
  exit "$exit_status"
}
trap cleanup EXIT

management_kubectl -n "$management_namespace" get secret "${cluster_name}-kubeconfig" \
  -o jsonpath='{.data.value}' |
  base64 --decode >"$workload_kubeconfig"
chmod 600 "$workload_kubeconfig"

target_node_json="$(workload_kubectl get node "$target_node" -o json)"
target_pool="$(jq -r '.metadata.labels["node.cluster.x-k8s.io/pool"] // ""' <<<"$target_node_json")"
target_cluster="$(jq -r '.metadata.annotations["cluster.x-k8s.io/cluster-name"] // ""' <<<"$target_node_json")"
machine_name="$(jq -r '.metadata.annotations["cluster.x-k8s.io/machine"] // ""' <<<"$target_node_json")"
node_ready="$(
  jq -r '[.status.conditions[] | select(.type == "Ready")][0].status // ""' \
    <<<"$target_node_json"
)"
node_was_unschedulable="$(jq -r '.spec.unschedulable // false' <<<"$target_node_json")"

if [ "$target_pool" != "runners-linux" ]; then
  echo "ERROR: $target_node belongs to pool $target_pool, not runners-linux" >&2
  exit 65
fi
if [ "$target_cluster" != "$cluster_name" ]; then
  echo "ERROR: $target_node belongs to cluster $target_cluster, not $cluster_name" >&2
  exit 65
fi
if [ -z "$machine_name" ]; then
  echo "ERROR: $target_node has no Cluster API Machine annotation" >&2
  exit 65
fi
if [ "$node_ready" != "True" ]; then
  echo "ERROR: $target_node is not Ready" >&2
  exit 65
fi

ready_runner_nodes="$(
  workload_kubectl get nodes \
    -l node.cluster.x-k8s.io/pool=runners-linux \
    -o json |
    jq '[.items[] |
      select(.metadata.deletionTimestamp == null) |
      select(any(.status.conditions[]; .type == "Ready" and .status == "True"))
    ] | length'
)"
if [ "$ready_runner_nodes" -lt 2 ]; then
  echo "ERROR: production has only $ready_runner_nodes Ready runner node(s); refusing rotation" >&2
  exit 65
fi

machine_json="$(
  management_kubectl -n "$management_namespace" \
    get machine.cluster.x-k8s.io "$machine_name" -o json
)"
machine_uid="$(jq -r '.metadata.uid' <<<"$machine_json")"
machine_cluster="$(jq -r '.metadata.labels["cluster.x-k8s.io/cluster-name"] // ""' <<<"$machine_json")"
machine_deletion_timestamp="$(jq -r '.metadata.deletionTimestamp // ""' <<<"$machine_json")"
machine_set="$(
  jq -r '.metadata.ownerReferences[]? |
    select(.kind == "MachineSet" and .controller == true) |
    .name' <<<"$machine_json"
)"
bare_metal_machine="$(
  jq -r '
    if .spec.infrastructureRef.kind == "HetznerBareMetalMachine"
    then .spec.infrastructureRef.name
    else ""
    end
  ' <<<"$machine_json"
)"

if [ "$machine_cluster" != "$cluster_name" ]; then
  echo "ERROR: Machine $machine_name belongs to cluster $machine_cluster" >&2
  exit 65
fi
if [ -n "$machine_deletion_timestamp" ]; then
  echo "ERROR: Machine $machine_name is already being deleted" >&2
  exit 65
fi
if [ -z "$machine_set" ] || [ -z "$bare_metal_machine" ]; then
  echo "ERROR: Machine $machine_name is not a bare-metal MachineDeployment member" >&2
  exit 65
fi

machine_set_pool="$(
  management_kubectl -n "$management_namespace" \
    get machineset.cluster.x-k8s.io "$machine_set" \
    -o jsonpath='{.metadata.labels.topology\.cluster\.x-k8s\.io/deployment-name}'
)"
if [ "$machine_set_pool" != "runners-linux" ]; then
  echo "ERROR: Machine $machine_name belongs to topology pool $machine_set_pool" >&2
  exit 65
fi

hosts_json="$(
  management_kubectl -n "$management_namespace" \
    get hetznerbaremetalhosts.infrastructure.cluster.x-k8s.io -o json
)"
matching_hosts="$(
  jq --arg consumer "$bare_metal_machine" \
    '[.items[] | select(.spec.consumerRef.name == $consumer)]' \
    <<<"$hosts_json"
)"
matching_host_count="$(jq 'length' <<<"$matching_hosts")"
if [ "$matching_host_count" -ne 1 ]; then
  echo "ERROR: expected one physical host for $bare_metal_machine, found $matching_host_count" >&2
  exit 65
fi

host_name="$(jq -r '.[0].metadata.name' <<<"$matching_hosts")"
host_uid="$(jq -r '.[0].metadata.uid' <<<"$matching_hosts")"
host_server_id="$(jq -r '.[0].spec.serverID' <<<"$matching_hosts")"
host_cluster="$(jq -r '.[0].metadata.labels["cluster.x-k8s.io/cluster-name"] // ""' <<<"$matching_hosts")"
host_deletion_timestamp="$(jq -r '.[0].metadata.deletionTimestamp // ""' <<<"$matching_hosts")"

if [ "$host_cluster" != "$cluster_name" ]; then
  echo "ERROR: physical host $host_name belongs to cluster $host_cluster" >&2
  exit 65
fi
if [ -z "$host_server_id" ] || [ "$host_server_id" = "null" ]; then
  echo "ERROR: physical host $host_name has no server identifier" >&2
  exit 65
fi
if [ -n "$host_deletion_timestamp" ]; then
  echo "ERROR: physical host $host_name is already being deleted" >&2
  exit 65
fi

echo "Validated replacement chain:"
echo "  Node:               $target_node"
echo "  Machine:            $machine_name"
echo "  bare-metal machine: $bare_metal_machine"
echo "  physical host:      $host_name (server $host_server_id)"

if [ "$node_was_unschedulable" != "true" ]; then
  workload_kubectl cordon "$target_node"
  cordoned_by_script=true
fi

mapfile -t runner_pods < <(
  workload_kubectl -n "$runner_namespace" get pods \
    --field-selector "spec.nodeName=$target_node" \
    -l tuist.dev/runner=true \
    -o json |
    jq -r '.items[].metadata.name'
)
for pod_name in "${runner_pods[@]}"; do
  workload_kubectl -n "$runner_namespace" label pod "$pod_name" \
    tuist.dev/runner-operator-drain=true \
    --overwrite
done

active_deadline=$((SECONDS + 2700))
while true; do
  runner_counts="$(
    workload_kubectl -n "$runner_namespace" get pods \
      --field-selector "spec.nodeName=$target_node" \
      -l tuist.dev/runner=true \
      -o json |
      jq '{
        active: [.items[] |
          select((.metadata.labels["tuist.dev/runner-pool-owner"] // "") != "")
        ] | length,
        total: (.items | length)
      }'
  )"
  active_runner_count="$(jq -r '.active' <<<"$runner_counts")"
  total_runner_count="$(jq -r '.total' <<<"$runner_counts")"
  if [ "$total_runner_count" -eq 0 ]; then
    break
  fi
  if [ "$SECONDS" -ge "$active_deadline" ]; then
    echo "ERROR: $total_runner_count runner pod(s), including $active_runner_count active job(s), remain after 45 minutes" >&2
    exit 70
  fi
  echo "Waiting for $active_runner_count active job(s) and $((total_runner_count - active_runner_count)) draining runner(s) on $target_node"
  sleep 15
done

workload_kubectl drain "$target_node" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --timeout=10m

replacement_started=true
management_kubectl -n "$management_namespace" \
  delete hetznerbaremetalhost.infrastructure.cluster.x-k8s.io "$host_name" \
  --wait=false
management_kubectl -n "$management_namespace" \
  delete machine.cluster.x-k8s.io "$machine_name" \
  --wait=false

replacement_host_uid=""
replacement_deadline=$((SECONDS + 1800))
finalizer_checked=false
while [ "$SECONDS" -lt "$replacement_deadline" ]; do
  current_host_json="$(
    management_kubectl -n "$management_namespace" \
      get hetznerbaremetalhost.infrastructure.cluster.x-k8s.io "$host_name" \
      -o json 2>/dev/null || true
  )"
  if [ -n "$current_host_json" ]; then
    current_host_uid="$(jq -r '.metadata.uid' <<<"$current_host_json")"
    if [ "$current_host_uid" != "$host_uid" ]; then
      replacement_host_uid="$current_host_uid"
      break
    fi
  fi

  if [ "$finalizer_checked" = "false" ] &&
    [ "$SECONDS" -ge $((replacement_deadline - 1500)) ] &&
    [ -n "$current_host_json" ]; then
    deletion_timestamp="$(jq -r '.metadata.deletionTimestamp // ""' <<<"$current_host_json")"
    current_server_id="$(jq -r '.spec.serverID' <<<"$current_host_json")"
    if [ -n "$deletion_timestamp" ] &&
      [ "$current_host_uid" = "$host_uid" ] &&
      [ "$current_server_id" = "$host_server_id" ]; then
      echo "Host deletion is still finalizing after five minutes; removing the exact stale finalizer"
      management_kubectl -n "$management_namespace" \
        patch hetznerbaremetalhost.infrastructure.cluster.x-k8s.io "$host_name" \
        --type=merge \
        -p '{"metadata":{"finalizers":[]}}'
    fi
    finalizer_checked=true
  fi
  sleep 15
done
if [ -z "$replacement_host_uid" ]; then
  echo "ERROR: physical host object was not recreated within 30 minutes" >&2
  exit 70
fi

replacement_bare_metal_machine=""
provision_deadline=$((SECONDS + 2700))
while [ "$SECONDS" -lt "$provision_deadline" ]; do
  replacement_host_json="$(
    management_kubectl -n "$management_namespace" \
      get hetznerbaremetalhost.infrastructure.cluster.x-k8s.io "$host_name" \
      -o json
  )"
  current_host_uid="$(jq -r '.metadata.uid' <<<"$replacement_host_json")"
  current_server_id="$(jq -r '.spec.serverID' <<<"$replacement_host_json")"
  replacement_bare_metal_machine="$(
    jq -r '.spec.consumerRef.name // ""' <<<"$replacement_host_json"
  )"
  provisioning_state="$(
    jq -r '.spec.status.provisioningState // ""' <<<"$replacement_host_json"
  )"

  if [ "$current_host_uid" = "$replacement_host_uid" ] &&
    [ "$current_server_id" = "$host_server_id" ] &&
    [ -n "$replacement_bare_metal_machine" ] &&
    [ "$replacement_bare_metal_machine" != "$bare_metal_machine" ] &&
    [ "$provisioning_state" = "provisioned" ]; then
    break
  fi
  replacement_bare_metal_machine=""
  echo "Waiting for server $host_server_id to be reinstalled from the current machine template"
  sleep 30
done
if [ -z "$replacement_bare_metal_machine" ]; then
  echo "ERROR: replacement host did not finish provisioning within 45 minutes" >&2
  exit 70
fi

replacement_machine=""
node_deadline=$((SECONDS + 1200))
while [ "$SECONDS" -lt "$node_deadline" ]; do
  replacement_machine_json="$(
    management_kubectl -n "$management_namespace" \
      get machines.cluster.x-k8s.io \
      -l "cluster.x-k8s.io/cluster-name=$cluster_name" \
      -o json |
      jq --arg infrastructure "$replacement_bare_metal_machine" \
        '[.items[] |
          select(.spec.infrastructureRef.name == $infrastructure)
        ][0] // {}'
  )"
  replacement_machine="$(jq -r '.metadata.name // ""' <<<"$replacement_machine_json")"
  replacement_machine_uid="$(jq -r '.metadata.uid // ""' <<<"$replacement_machine_json")"
  replacement_node="$(
    jq -r '.status.nodeRef.name // ""' <<<"$replacement_machine_json"
  )"
  if [ -n "$replacement_machine" ] &&
    [ "$replacement_machine_uid" != "$machine_uid" ] &&
    [ -n "$replacement_node" ]; then
    replacement_node_json="$(
      workload_kubectl get node "$replacement_node" -o json 2>/dev/null || true
    )"
    replacement_ready="$(
      jq -r '[.status.conditions[]? | select(.type == "Ready")][0].status // ""' \
        <<<"$replacement_node_json"
    )"
    if [ "$replacement_ready" = "True" ]; then
      break
    fi
  fi
  replacement_machine=""
  echo "Waiting for the replacement workload node to become Ready"
  sleep 15
done
if [ -z "$replacement_machine" ]; then
  echo "ERROR: replacement workload node did not become Ready within 20 minutes" >&2
  exit 70
fi

replacement_pool="$(
  jq -r '.metadata.labels["node.cluster.x-k8s.io/pool"] // ""' \
    <<<"$replacement_node_json"
)"
replacement_outdated_taint="$(
  jq -r '[.spec.taints[]? |
    select(.key == "node.cluster.x-k8s.io/outdated-revision")
  ] | length' <<<"$replacement_node_json"
)"
capacity_memory="$(jq -r '.status.capacity.memory' <<<"$replacement_node_json")"
allocatable_memory="$(jq -r '.status.allocatable.memory' <<<"$replacement_node_json")"

quantity_to_kibibytes() {
  local quantity="$1"
  case "$quantity" in
    *Ki) printf '%s\n' "${quantity%Ki}" ;;
    *Mi) printf '%s\n' "$(( ${quantity%Mi} * 1024 ))" ;;
    *Gi) printf '%s\n' "$(( ${quantity%Gi} * 1024 * 1024 ))" ;;
    *) printf '%s\n' "$(( quantity / 1024 ))" ;;
  esac
}

capacity_kibibytes="$(quantity_to_kibibytes "$capacity_memory")"
allocatable_kibibytes="$(quantity_to_kibibytes "$allocatable_memory")"
reserved_kibibytes=$((capacity_kibibytes - allocatable_kibibytes))
minimum_reserved_kibibytes=$((20 * 1024 * 1024))

if [ "$replacement_pool" != "runners-linux" ]; then
  echo "ERROR: replacement node is in pool $replacement_pool" >&2
  exit 70
fi
if [ "$replacement_outdated_taint" -ne 0 ]; then
  echo "ERROR: replacement node still carries the outdated-revision taint" >&2
  exit 70
fi
if [ "$reserved_kibibytes" -lt "$minimum_reserved_kibibytes" ]; then
  echo "ERROR: replacement node reserves less than 20 GiB of host memory" >&2
  exit 70
fi

echo "Replacement verified:"
echo "  Node:               $replacement_node"
echo "  Machine:            $replacement_machine"
echo "  bare-metal machine: $replacement_bare_metal_machine"
echo "  physical host:      $host_name (server $host_server_id)"
echo "  memory:             $allocatable_memory allocatable of $capacity_memory"
echo "  host reservation:   $reserved_kibibytes Ki"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Production runner node rotation"
    echo
    echo "- Replaced node: \`$target_node\`"
    echo "- Replacement node: \`$replacement_node\`"
    echo "- Replacement Machine: \`$replacement_machine\`"
    echo "- Physical server: \`$host_server_id\`"
    echo "- Memory: \`$allocatable_memory\` allocatable of \`$capacity_memory\`"
    echo "- Reserved host memory: \`$reserved_kibibytes Ki\`"
  } >>"$GITHUB_STEP_SUMMARY"
fi
