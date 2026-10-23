#!/usr/bin/env bash
#MISE description="Apply the Talos machine config patches in infra/k8s/mgmt/talos/patches/ to every management control-plane node, from a Job inside the cluster. Prints what would change; pass --apply to apply it."
#USAGE flag "--apply" help="Apply the patches instead of only printing what they change"

# Needs KUBECONFIG for the management cluster.
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
# the next node waits until the API server, the node and every Deployment
# are healthy again.
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

job_manifest() {
  local job_name="$1"
  shift
  jq -n --arg name "$job_name" --arg namespace "$NAMESPACE" --arg image "$TALOSCTL_IMAGE" \
    --argjson args "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '{
    apiVersion: "batch/v1",
    kind: "Job",
    metadata: {name: $name, namespace: $namespace},
    spec: {
      backoffLimit: 0,
      activeDeadlineSeconds: 300,
      template: {
        spec: {
          restartPolicy: "Never",
          securityContext: {runAsNonRoot: true, runAsUser: 65534, runAsGroup: 65534, seccompProfile: {type: "RuntimeDefault"}},
          containers: [{
            name: "talosctl",
            image: $image,
            args: $args,
            securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}},
            volumeMounts: [
              {name: "talos-secrets", mountPath: "/var/run/secrets/talos.dev", readOnly: true},
              {name: "patches", mountPath: "/patches", readOnly: true}
            ]
          }],
          volumes: [
            {name: "talos-secrets", secret: {secretName: "talos-patcher"}},
            {name: "patches", configMap: {name: "talos-patches"}}
          ]
        }
      }
    }
  }'
}

# Runs talosctl in a Job and prints its output. The Job is deleted afterwards
# so the full dry-run diff does not stay in the cluster's pod logs.
run_talosctl() {
  local job_name="$1"
  shift
  kubectl -n "$NAMESPACE" delete job "$job_name" --ignore-not-found >/dev/null
  job_manifest "$job_name" "$@" | kubectl apply -f - >/dev/null

  local status=""
  for _ in $(seq 1 120); do
    status="$(kubectl -n "$NAMESPACE" get job "$job_name" -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null || true)"
    [[ "$status" == 1/* || "$status" == */1 ]] && break
    sleep 5
  done

  local output=""
  for _ in $(seq 1 12); do
    output="$(kubectl -n "$NAMESPACE" logs "job/$job_name" 2>/dev/null)" && break
    sleep 5
  done
  kubectl -n "$NAMESPACE" delete job "$job_name" --ignore-not-found >/dev/null 2>&1 || true

  if [[ "$status" != 1/* && -z "$output" ]]; then
    echo "Job $job_name produced no output within 10 minutes. If it never started a pod, kube-controller-manager is probably down; fix the node with talosctl over the tailnet." >&2
  fi
  printf '%s\n' "$output"
  [[ "$status" == 1/* ]]
}

wait_until_healthy() {
  local node="$1"
  sleep 30
  for _ in $(seq 1 120); do
    kubectl get --raw /readyz >/dev/null 2>&1 && break
    sleep 5
  done
  kubectl wait --for=condition=Ready "node/$node" --timeout=10m >/dev/null
  kubectl -n kube-system wait --for=condition=Ready pod -l tier=control-plane \
    --field-selector "spec.nodeName=$node" --timeout=10m >/dev/null
  kubectl wait --for=condition=Available deployment --all --all-namespaces --timeout=15m >/dev/null

  # Deployments stay Available while a control-plane component crash-loops,
  # so require the static pods to stay up without restarting for a while.
  local restarts
  restarts="$(control_plane_restarts "$node")"
  sleep 90
  [[ "$(control_plane_restarts "$node")" == "$restarts" ]] ||
    fail "a control-plane pod on $node restarted after the change; check kube-system and fix it with talosctl over the tailnet"
  kubectl -n kube-system wait --for=condition=Ready pod -l tier=control-plane \
    --field-selector "spec.nodeName=$node" --timeout=10s >/dev/null ||
    fail "a control-plane pod on $node is not Ready after the change"
}

control_plane_restarts() {
  kubectl -n kube-system get pods -l tier=control-plane --field-selector "spec.nodeName=$1" \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.containerStatuses[0].restartCount}{" "}{end}'
}

nodes="$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')"
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

if ! $apply; then
  echo "==> Dry run; pass --apply to apply these changes"
fi
