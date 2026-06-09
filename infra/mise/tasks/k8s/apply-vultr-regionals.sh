#!/usr/bin/env bash
#MISE description="Install CAPVULTR on the management cluster and diff/apply Vultr regional Kura CAPI clusters."
#USAGE arg "[mode]" help="install-provider | diff | apply (default: apply)"

set -euo pipefail

MODE="${1:-apply}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
NAMESPACE="${ORG_NAMESPACE:-org-tuist}"
MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-${KUBECONFIG:-$HOME/.kube/tuist-mgmt.yaml}}"
VULTR_CONFIG_VAULT="${VULTR_CONFIG_VAULT:-Founders}"
VULTR_CONFIG_ITEM="${VULTR_CONFIG_ITEM:-vultr-tuist-workloads}"
CAPVULTR_VERSION="${CAPVULTR_VERSION:-v0.4.0}"
CAPVULTR_COMPONENTS_URL="https://github.com/vultr/cluster-api-provider-vultr/releases/download/${CAPVULTR_VERSION}/infrastructure-components.yaml"
TEMPLATE_DIR="$REPO_ROOT/infra/k8s/clusters/vultr"
IMAGE_CATALOG="${VULTR_IMAGE_CATALOG:-$TEMPLATE_DIR/images.yaml}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
err() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; }

op_field() {
  local label="$1"
  local op_args=(
    item get "$VULTR_CONFIG_ITEM"
    --vault "$VULTR_CONFIG_VAULT"
    --fields "label=${label}"
    --reveal
  )

  if [ -z "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    op_args+=(--account "${OP_ACCOUNT:-tuist.1password.com}")
  fi

  op "${op_args[@]}" 2>/dev/null || true
}

yaml_value() {
  local key="$1"
  awk -F: -v key="$key" '
    $1 == key {
      value = $0
      sub("^[^:]*:[[:space:]]*", "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$IMAGE_CATALOG"
}

load_vultr_token() {
  VULTR_API_KEY="${VULTR_API_KEY:-$(op_field password)}"

  if [ -z "$VULTR_API_KEY" ]; then
    err "missing Vultr API token; set VULTR_API_KEY or add password to 1Password item $VULTR_CONFIG_VAULT/$VULTR_CONFIG_ITEM"
    exit 1
  fi
}

load_vultr_cluster_config() {
  VULTR_CAPI_SNAPSHOT_ID="${VULTR_CAPI_SNAPSHOT_ID:-$(yaml_value snapshotID)}"
  VULTR_CONTROL_PLANE_PLAN_ID="${VULTR_CONTROL_PLANE_PLAN_ID:-$(yaml_value controlPlanePlanID)}"
  VULTR_WORKER_PLAN_ID="${VULTR_WORKER_PLAN_ID:-$(yaml_value workerPlanID)}"

  VULTR_CONTROL_PLANE_PLAN_ID="${VULTR_CONTROL_PLANE_PLAN_ID:-vc2-4c-8gb}"
  VULTR_WORKER_PLAN_ID="${VULTR_WORKER_PLAN_ID:-vc2-4c-8gb}"

  if [ -z "$VULTR_CAPI_SNAPSHOT_ID" ]; then
    err "missing Vultr CAPI snapshot; set VULTR_CAPI_SNAPSHOT_ID or commit snapshotID in $IMAGE_CATALOG"
    exit 1
  fi
}

sed_escape() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

render_template() {
  local template="$1"
  sed \
    -e "s|\${VULTR_CAPI_SNAPSHOT_ID}|$(sed_escape "$VULTR_CAPI_SNAPSHOT_ID")|g" \
    -e "s|\${VULTR_CONTROL_PLANE_PLAN_ID}|$(sed_escape "$VULTR_CONTROL_PLANE_PLAN_ID")|g" \
    -e "s|\${VULTR_WORKER_PLAN_ID}|$(sed_escape "$VULTR_WORKER_PLAN_ID")|g" \
    "$template"
}

install_provider() {
  log "Installing CAPVULTR ${CAPVULTR_VERSION}"
  kubectl --kubeconfig "$MGMT_KUBECONFIG" apply \
    --server-side --force-conflicts \
    --field-manager=tuist-mgmt-cluster-apply \
    -f "$CAPVULTR_COMPONENTS_URL"

  kubectl --kubeconfig "$MGMT_KUBECONFIG" wait \
    --for=condition=Established \
    crd/vultrclusters.infrastructure.cluster.x-k8s.io \
    crd/vultrmachines.infrastructure.cluster.x-k8s.io \
    crd/vultrmachinetemplates.infrastructure.cluster.x-k8s.io \
    --timeout=2m

  kubectl --kubeconfig "$MGMT_KUBECONFIG" -n capvultr-system create secret generic capvultr-manager-credentials \
    --from-literal=apiKey="$VULTR_API_KEY" \
    --dry-run=client -o yaml | kubectl --kubeconfig "$MGMT_KUBECONFIG" apply \
      --server-side --force-conflicts \
      --field-manager=tuist-mgmt-cluster-apply \
      -f -

  kubectl --kubeconfig "$MGMT_KUBECONFIG" -n capvultr-system rollout restart deploy/capvultr-controller-manager
  kubectl --kubeconfig "$MGMT_KUBECONFIG" -n capvultr-system rollout status deploy/capvultr-controller-manager --timeout=5m
}

diff_clusters() {
  log "Diffing Vultr regional CAPI clusters"
  for template in "$TEMPLATE_DIR"/*.yaml.tmpl; do
    [ -e "$template" ] || continue
    echo "==> $template"
    render_template "$template" | kubectl --kubeconfig "$MGMT_KUBECONFIG" diff -f - || true
  done
}

apply_clusters() {
  log "Applying Vultr regional CAPI clusters"
  for template in "$TEMPLATE_DIR"/*.yaml.tmpl; do
    [ -e "$template" ] || continue
    echo "==> $template"
    render_template "$template" | kubectl --kubeconfig "$MGMT_KUBECONFIG" apply -f -
  done
}

case "$MODE" in
  install-provider)
    load_vultr_token
    install_provider
    ;;
  diff)
    load_vultr_cluster_config
    diff_clusters
    ;;
  apply)
    load_vultr_cluster_config
    apply_clusters
    ;;
  *)
    err "unsupported mode '$MODE' (expected install-provider, diff, or apply)"
    exit 64
    ;;
esac
