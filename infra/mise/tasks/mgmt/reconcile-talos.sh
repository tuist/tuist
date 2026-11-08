#!/usr/bin/env bash
#MISE description="Join the control-plane nodes listed in infra/k8s/mgmt/talos/hetzner.yaml and apply the Talos machine config patches in infra/k8s/mgmt/talos/patches/ to every one, from Jobs inside the cluster. Prints what would change; pass --apply to apply it."
#USAGE flag "--apply" help="Join nodes and apply the patches instead of only printing what would change"

# Needs KUBECONFIG for the management cluster.
#
# A node listed in hetzner.yaml but missing from the cluster is joined
# first: reconcile-hetzner.sh created its server without a machine config,
# so Talos waits in maintenance mode at the node's private IP. A Job copies
# an existing control-plane node's machine config to it, which makes it join
# etcd and register with Kubernetes. Nodes join one at a time, only while
# every etcd member votes, and the next waits until the new node is healthy
# and a voting etcd member. Removing a node from hetzner.yaml does not remove
# it from etcd or Kubernetes.
#
# Talos's strategic-merge patches append to lists, so a patch applied twice
# would duplicate its list entries. Each patch is therefore applied as
# set, clear, set in one call. The clear copy replaces every list in the
# patch with `$patch: delete`. The first set makes every list exist, so the
# delete cannot fail on a missing path, and the last set leaves exactly the
# declared entries. A patch owns every list it mentions: live entries it does
# not declare are removed. Maps and scalars merge as usual.
#
# The Job applies with --mode no-reboot, so a change that needs a reboot
# fails instead of rebooting a node. Nodes are patched one at a time, and
# the next node waits until the API server, the node, its control-plane pods
# (Ready without restarting for 90 seconds) and every Deployment are healthy
# again.
#
# Only added and removed lines are printed: talosctl's dry-run diff also
# shows unchanged context, which includes private keys, and this
# repository's Actions logs are public.
#
# The Talos credential exists only while this script runs. Talos mints it
# into a Secret for the talos.dev ServiceAccount, and the Secret is readable
# by every principal with cluster-wide secret read. So the script creates
# the ServiceAccount at the start, after removing any left over from an
# interrupted run, and deletes it and the Secret on exit. A certificate
# copied during a run stays valid until it expires (Talos issues them for
# 6 hours).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PATCHES_DIR="$REPO_ROOT/infra/k8s/mgmt/talos/patches"
PATCHER_MANIFEST="$REPO_ROOT/infra/k8s/mgmt/talos-patcher.yaml"
NAMESPACE="mgmt-talos"
TALOSCTL_IMAGE="ghcr.io/siderolabs/talosctl:v1.13.11"
JOIN_IMAGE="busybox:1.37.0"
SPEC="$REPO_ROOT/infra/k8s/mgmt/talos/hetzner.yaml"

apply=false
if [[ "${1:-}" == "--apply" ]]; then
  apply=true
fi

fail() {
  echo "error: $*" >&2
  exit 1
}

# Keeps talosctl's messages and changed lines; drops diff context and headers.
safe_output() { grep -vE '^( |@@|\+\+\+ |--- |$)' || true; }

revoke_talos_credential() {
  kubectl -n "$NAMESPACE" delete serviceaccounts.talos.dev talos-patcher --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete secret talos-patcher --ignore-not-found >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    kubectl -n "$NAMESPACE" get secret talos-patcher >/dev/null 2>&1 || return 0
    sleep 2
  done
  echo "warning: Secret $NAMESPACE/talos-patcher still exists" >&2
}

workdir="$(mktemp -d)"
cleanup() {
  revoke_talos_credential
  rm -rf "$workdir"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

patch_args=()
for patch in "$PATCHES_DIR"/*.yaml; do
  name="$(basename "$patch" .yaml)"
  [[ "$(yq ea '[.] | length' "$patch")" == "1" ]] || fail "$patch must hold exactly one YAML document"
  yq -e 'tag == "!!map"' "$patch" >/dev/null || fail "$patch must be a strategic-merge patch (a YAML map)"
  cp "$patch" "$workdir/$name.yaml"
  # shellcheck disable=SC2016 # `$patch: delete` is a literal Talos directive.
  yq '(.. | select(tag == "!!seq")) |= {"$patch": "delete"}' "$patch" >"$workdir/$name.clear.yaml"
  patch_args+=(--patch "@/patches/$name.yaml" --patch "@/patches/$name.clear.yaml" --patch "@/patches/$name.yaml")
done
(( ${#patch_args[@]} > 0 )) || fail "no patches in $PATCHES_DIR"

revoke_talos_credential
kubectl apply -f "$PATCHER_MANIFEST" >/dev/null ||
  fail "could not apply $PATCHER_MANIFEST; if the talos.dev ServiceAccount kind is unknown, apply patches/10-talos-api-access.yaml by hand first (infra/k8s/mgmt/talos/README.md)"
for _ in $(seq 1 30); do
  kubectl -n "$NAMESPACE" get secret talos-patcher >/dev/null 2>&1 && break
  sleep 2
done
kubectl -n "$NAMESPACE" get secret talos-patcher >/dev/null || fail "Talos did not create Secret $NAMESPACE/talos-patcher"
kubectl -n "$NAMESPACE" create configmap talos-patches --from-file="$workdir" --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# Prints a Job that runs one container with the Talos credential mounted.
# The container's own volume mounts refer to the extra volumes.
job_manifest() {
  local job_name="$1" deadline="$2" container="$3" volumes="$4"
  jq -n --arg name "$job_name" --arg namespace "$NAMESPACE" --argjson deadline "$deadline" \
    --arg node "$TALOS_JOB_NODE" \
    --argjson container "$container" --argjson volumes "$volumes" '{
    apiVersion: "batch/v1",
    kind: "Job",
    metadata: {name: $name, namespace: $namespace},
    spec: {
      backoffLimit: 0,
      activeDeadlineSeconds: $deadline,
      template: {
        spec: {
          restartPolicy: "Never",
          nodeSelector: {"kubernetes.io/hostname": $node},
          tolerations: [{key: "node-role.kubernetes.io/control-plane", operator: "Exists", effect: "NoSchedule"}],
          securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, seccompProfile: {type: "RuntimeDefault"}},
          containers: [$container + {
            securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}},
            volumeMounts: ([{name: "talos-secrets", mountPath: "/var/run/secrets/talos.dev", readOnly: true}] + $container.volumeMounts)
          }],
          volumes: ([{name: "talos-secrets", secret: {secretName: "talos-patcher"}}] + $volumes)
        }
      }
    }
  }'
}

# Runs talosctl in a Job and prints its output.
run_talosctl() {
  local job_name="$1"
  shift
  local container
  container="$(jq -n --arg image "$TALOSCTL_IMAGE" --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{
    name: "talosctl",
    image: $image,
    args: $args,
    volumeMounts: [{name: "patches", mountPath: "/patches", readOnly: true}]
  }')"
  run_job "$job_name" 300 "$container" '[{"name": "patches", "configMap": {"name": "talos-patches"}}]'
}

# Runs a Job and prints its output. The Job and its pod are deleted
# afterwards so the full dry-run diff does not stay in the cluster's pod logs.
run_job() {
  local job_name="$1" deadline="$2"
  kubectl -n "$NAMESPACE" delete job "$job_name" --ignore-not-found >/dev/null
  job_manifest "$@" | kubectl apply -f - >/dev/null

  # The pod phase comes from the kubelet. The Job status depends on
  # kube-controller-manager, which a bad patch can take down.
  local status=""
  for _ in $(seq 1 $((deadline / 5 + 60))); do
    status="$(kubectl -n "$NAMESPACE" get pods -l "job-name=$job_name" -o jsonpath='{.items[*].status.phase}' 2>/dev/null || true)"
    [[ "$status" == Succeeded || "$status" == Failed ]] && break
    sleep 5
  done

  local output=""
  for _ in $(seq 1 12); do
    output="$(kubectl -n "$NAMESPACE" logs "job/$job_name" 2>/dev/null)" && break
    sleep 5
  done
  # Delete the pod too: garbage collection of a deleted Job's pods also
  # depends on kube-controller-manager.
  kubectl -n "$NAMESPACE" delete job "$job_name" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$NAMESPACE" delete pods -l "job-name=$job_name" --ignore-not-found >/dev/null 2>&1 || true

  if [[ "$status" != Succeeded && -z "$output" ]]; then
    echo "Job $job_name produced no output (pod phase: ${status:-missing}); check scheduling, image pulls, pod networking and kube-controller-manager on $TALOS_JOB_NODE." >&2
  fi
  printf '%s\n' "$output"
  [[ "$status" == Succeeded ]]
}

wait_until_healthy() {
  local node="$1"
  sleep 30
  for _ in $(seq 1 120); do
    kubectl get --raw /readyz >/dev/null 2>&1 && break
    sleep 5
  done
  kubectl wait --for=condition=Ready "node/$node" --timeout=10m >/dev/null

  # Deployments stay Available while a control-plane component crash-loops,
  # and an API server restart briefly takes the controller-manager and
  # scheduler down with it. So wait until the node's control-plane pods have
  # all been Ready, with the same pods and restart counts, for a full window.
  local deadline=$((SECONDS + 900)) state="" previous="" stable_since=$SECONDS
  while true; do
    state="$(control_plane_state "$node")"
    if [[ "$state" != "$previous" || "$state" == *"=false"* || -z "$state" ]]; then
      if [[ "$state" != "$previous" ]]; then
        echo "control-plane stability window reset on $node: ${state:-pods missing or API unavailable}"
      fi
      previous="$state"
      stable_since=$SECONDS
    elif (( SECONDS - stable_since >= 90 )); then
      break
    fi
    (( SECONDS < deadline )) ||
      fail "the control-plane pods on $node did not stay Ready for 90 seconds within 15 minutes of the change; check kube-system and fix the node with talosctl over the tailnet"
    sleep 10
  done
  kubectl wait --for=condition=Available deployment --all --all-namespaces --timeout=15m >/dev/null
}

# One "name=uid:restarts:ready=boolean" entry per control-plane pod.
control_plane_state() {
  kubectl -n kube-system get pods -l tier=control-plane --field-selector "spec.nodeName=$1" \
    -o json 2>/dev/null | jq -L "$REPO_ROOT/infra/mise/tasks/mgmt" -r 'include "health"; control_plane_state' || true
}

control_plane_nodes() {
  kubectl get nodes -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
}

# Prints "hostname learner" for each etcd member, as the node at $1 sees them.
etcd_members() {
  local output
  output="$(run_talosctl talos-etcd-members --nodes "$1" etcd members)" || return 1
  printf '%s\n' "$output" | awk 'NR > 1 && NF >= 6 {print $3, $NF}' | sort
}

# Waits until etcd's members are exactly the given hostnames, all voting.
wait_for_etcd_members() {
  local source_ip="$1" want members="" deadline=$((SECONDS + 900))
  shift
  want="$(printf '%s false\n' "$@" | sort)"
  while true; do
    members="$(etcd_members "$source_ip" || true)"
    [[ "$members" == "$want" ]] && return 0
    if (( SECONDS >= deadline )); then
      printf 'etcd members (hostname, learner):\n%s\n' "$members" >&2
      fail "etcd did not reach the voting members $* within 15 minutes"
    fi
    sleep 15
  done
}

# Runs in the join Job. Copies the machine config of the node at SOURCE_IP
# to the node at NODE_IP, which waits in Talos maintenance mode. A configured
# node refuses an insecure apply, so this cannot overwrite a member.
read -r -d '' JOIN_SCRIPT <<'EOF' || true
set -eu
talosctl() { /opt/talosctl/talosctl "$@"; }
if talosctl --nodes "$NODE_IP" version >/dev/null 2>&1; then
  echo "$NODE_IP already has a machine config"
  exit 0
fi
talosctl --nodes "$SOURCE_IP" get machineconfig persistent -o jsonpath='{.spec}' >/config/config.yaml
grep -qE '^ +type: controlplane( |$)' /config/config.yaml || {
  echo "the machine config of $SOURCE_IP is not a control-plane config" >&2
  exit 1
}
for _ in $(seq 1 60); do
  if talosctl apply-config --insecure --nodes "$NODE_IP" --endpoints "$NODE_IP" --file /config/config.yaml; then
    echo "applied the control-plane machine config to $NODE_IP"
    exit 0
  fi
  sleep 10
done
echo "$NODE_IP did not accept a machine config within 10 minutes" >&2
exit 1
EOF

# The machine config holds the cluster's private keys, so the Job keeps it
# in a memory-backed volume and prints nothing of it. talosctl comes from
# its image as a volume: the image has no shell to run the copy with.
join_node() {
  local node="$1" node_ip="$2" source_ip="$3" container volumes
  container="$(jq -n --arg image "$JOIN_IMAGE" --arg node_ip "$node_ip" --arg source_ip "$source_ip" --arg script "$JOIN_SCRIPT" '{
    name: "join",
    image: $image,
    command: ["sh", "-c", $script],
    env: [
      {name: "NODE_IP", value: $node_ip},
      {name: "SOURCE_IP", value: $source_ip},
      {name: "TALOSCONFIG", value: "/var/run/secrets/talos.dev/config"}
    ],
    volumeMounts: [
      {name: "talosctl", mountPath: "/opt/talosctl", readOnly: true},
      {name: "config", mountPath: "/config"}
    ]
  }')"
  volumes="$(jq -n --arg image "$TALOSCTL_IMAGE" '[
    {name: "talosctl", image: {reference: $image, pullPolicy: "IfNotPresent"}},
    {name: "config", emptyDir: {medium: "Memory", sizeLimit: "1Mi"}}
  ]')"
  run_job "talos-join-$node" 900 "$container" "$volumes"
}

# Control-plane nodes listed in hetzner.yaml that are not in the cluster
# yet, as "name privateIP", in the order listed.
registered="$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')"
# Keep management Jobs on an existing Ready member. A new member's broken
# overlay must fail the explicit network gate, not strand an etcd query Job.
TALOS_JOB_NODE="$(kubectl get nodes -l node-role.kubernetes.io/control-plane -o json | jq -r '
  [.items[] | select(.spec.unschedulable != true and any(.status.conditions[]; .type == "Ready" and .status == "True"))] |
  sort_by(.metadata.name) | .[0].metadata.name // empty')"
[[ -n "$TALOS_JOB_NODE" ]] || fail "no Ready, uncordoned control-plane node for Talos Jobs"
pending="$(yq -r '.nodes[] | .name + " " + .privateIP' "$SPEC" |
  while read -r name ip; do grep -qxF "$name" <<<"$registered" || echo "$name $ip"; done)"

if [[ -n "$pending" ]]; then
  current="$(control_plane_nodes)"
  [[ -n "$current" ]] || fail "no control-plane nodes found"
  source_ip="$(kubectl get node "$TALOS_JOB_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
  echo "==> etcd members (hostname, learner)"
  etcd_members "$source_ip" || fail "could not list the etcd members through $source_ip"

  while read -r node node_ip <&3; do
    echo "==> Join $node ($node_ip)"
    if ! $apply; then
      echo "would apply the control-plane machine config of $source_ip to $node_ip in maintenance mode"
      continue
    fi
    # A new member changes etcd's quorum, so only join while every member votes.
    read -r -a members <<<"$(control_plane_nodes | awk '{print $1}' | tr '\n' ' ')"
    wait_for_etcd_members "$source_ip" "${members[@]}"
    if ! result="$(join_node "$node" "$node_ip" "$source_ip")"; then
      printf '%s\n' "$result"
      fail "joining $node failed; the server must be waiting in Talos maintenance mode at $node_ip"
    fi
    printf '%s\n' "$result"

    echo "waiting for $node to register"
    deadline=$((SECONDS + 1200))
    until kubectl get node "$node" >/dev/null 2>&1; do
      (( SECONDS < deadline )) || fail "$node did not register within 20 minutes of receiving its machine config"
      sleep 10
    done
    kubectl wait --for=condition=Ready "node/$node" --timeout=10m >/dev/null
    "$REPO_ROOT/infra/mise/tasks/mgmt/check-pod-network.sh"
    wait_until_healthy "$node"
    registered_ip="$(kubectl get node "$node" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
    [[ "$registered_ip" == "$node_ip" ]] || fail "$node registered with InternalIP $registered_ip, hetzner.yaml says $node_ip"
    echo "waiting for $node to become a voting etcd member"
    wait_for_etcd_members "$source_ip" "${members[@]}" "$node"
  done 3<<<"$pending"
fi

nodes="$(control_plane_nodes)"
[[ -n "$nodes" ]] || fail "no control-plane nodes found"

while read -r node node_ip <&3; do
  echo "==> $node ($node_ip)"
  if ! plan="$(run_talosctl "talos-plan-$node" --nodes "$node_ip" patch machineconfig "${patch_args[@]}" --dry-run)"; then
    printf '%s\n' "$plan" | safe_output
    fail "planning the patches for $node failed"
  fi
  changes="$(printf '%s\n' "$plan" | grep -E '^[+-]' | grep -vE '^(\+\+\+ |--- )' || true)"
  if [[ -z "$changes" ]]; then
    echo "no changes"
    continue
  fi
  printf '%s\n' "$changes"

  if $apply; then
    if ! result="$(run_talosctl "talos-apply-$node" --nodes "$node_ip" patch machineconfig "${patch_args[@]}" --mode no-reboot)"; then
      printf '%s\n' "$result" | safe_output
      fail "applying the patches to $node failed"
    fi
    printf '%s\n' "$result" | safe_output
    echo "waiting for the API server, $node and every Deployment to be healthy"
    wait_until_healthy "$node"
  fi
done 3<<<"$nodes"

if $apply; then
  "$REPO_ROOT/infra/mise/tasks/mgmt/reconcile-flannel.sh" --apply
else
  "$REPO_ROOT/infra/mise/tasks/mgmt/reconcile-flannel.sh"
fi

if ! $apply; then
  echo "==> Dry run; pass --apply to apply these changes"
fi
