#!/usr/bin/env bash
#MISE description="Install or upgrade the Tuist platform chart (cert-manager, ESO, external-dns, metrics-server, and optionally ingress-nginx) on a workload cluster. Idempotent — safe to run on every deploy."
#USAGE arg "<kubeconfig>" help="Path to the workload cluster kubeconfig"
#USAGE arg "<cluster_name>" help="Cluster name, used for the external-dns owner ID and, for app clusters, the ingress LoadBalancer name"

# Brings a workload cluster to the desired state of the platform chart
# at HEAD: cert-manager + ClusterIssuer + external-dns +
# external-secrets + metrics-server, plus ingress-nginx on app-serving
# clusters.
# Designed to run from CI on every deploy so a
# half-bootstrapped cluster self-heals instead of silently breaking
# downstream installs that depend on cert-manager.io/v1 Certificate.
#
# Reads the Cloudflare DNS-01 API token from `CLOUDFLARE_API_TOKEN` if
# set (CI wires it from the workflow's 1Password integration). Falls
# back to `op read` for local invocations from bootstrap-workload.

set -euo pipefail

WL_KUBECONFIG="$1"
CLUSTER_NAME="$2"
REPO_ROOT="$(git rev-parse --show-toplevel)"
CHART_PATH="$REPO_ROOT/infra/helm/platform"
IS_KURA_REGIONAL_CLUSTER=false

if [[ "$CLUSTER_NAME" == tuist-kura-* ]]; then
  IS_KURA_REGIONAL_CLUSTER=true
fi

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ ! -r "$WL_KUBECONFIG" ]; then
  echo "ERROR: kubeconfig not readable: $WL_KUBECONFIG" >&2
  exit 1
fi

derive_region_from_nodes() {
  KUBECONFIG="$WL_KUBECONFIG" kubectl get nodes \
    -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/region}{"\n"}{end}' |
    awk 'NF { print; exit }'
}

derive_region_from_ingress_service() {
  KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get service platform-ingress-nginx-controller \
    -o jsonpath='{.metadata.annotations.load-balancer\.hetzner\.cloud/location}' 2>/dev/null || true
}

# HCCM stamps hcloud-backed nodes with topology.kubernetes.io/region
# (e.g. ash, hil, fsn1). Mixed clusters can also carry bare-metal
# runner nodes that do not have that label, so scan all nodes instead
# of assuming `.items[0]` is an hcloud VM.
REGION="$(derive_region_from_nodes)"
if [ -z "$REGION" ] && [ "$IS_KURA_REGIONAL_CLUSTER" = false ]; then
  REGION="$(derive_region_from_ingress_service)"
fi
if [ -z "$REGION" ] && [ "$IS_KURA_REGIONAL_CLUSTER" = false ]; then
  echo "ERROR: could not derive Hetzner location from topology.kubernetes.io/region on any node or from the existing ingress Service annotation on $WL_KUBECONFIG" >&2
  exit 1
fi
if [ -n "$REGION" ]; then
  log "Platform install for $CLUSTER_NAME (region $REGION)"
else
  log "Platform install for $CLUSTER_NAME"
fi

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN="$(op read --account tuist.1password.com \
    "op://Founders/cloudflare-tuist-dns/credential")"
fi

helm dependency update "$CHART_PATH" >/dev/null

KUBECONFIG="$WL_KUBECONFIG" kubectl create namespace platform \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform create secret generic cloudflare-api-token \
  --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
unset CLOUDFLARE_API_TOKEN

HELM_SET_ARGS=(
  --set "external-dns.txtOwnerId=${CLUSTER_NAME}-platform"
)
HELM_VALUES_ARGS=(-f "$CHART_PATH/values-hetzner.yaml")

if [ "$IS_KURA_REGIONAL_CLUSTER" = true ]; then
  log "Regional Kura cluster detected; skipping ingress-nginx install"
  HELM_VALUES_ARGS+=(-f "$CHART_PATH/values-kura-region.yaml")
else
  HELM_SET_ARGS+=(
    --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/location=${REGION}"
    --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/name=${CLUSTER_NAME}-ingress"
  )
fi

# Sized for a cold cluster: cert-manager CRDs, webhooks, and, on app
# clusters, ingress-nginx admission hooks and LB provision can take
# several minutes. 15m absorbs that with headroom; steady-state runs
# finish in under a minute and exit as soon as helm finds nothing to
# roll out.
HELM_TIMEOUT="15m"

# Helm installs chart CRDs only on `install`, not on `upgrade`. Some
# regional clusters predate the platform chart's cert-manager wiring, so
# an upgrade can see `clusterissuers.cert-manager.io` missing forever.
# Apply the cert-manager chart CRDs explicitly before templating our
# ClusterIssuer.
if ! KUBECONFIG="$WL_KUBECONFIG" kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
  log "ClusterIssuer CRD missing; applying cert-manager CRDs"

  cert_manager_chart="$(
    find "$CHART_PATH/charts" -maxdepth 1 -name 'cert-manager-*.tgz' |
      sort |
      tail -n 1
  )"

  if [ -z "$cert_manager_chart" ]; then
    echo "ERROR: cert-manager chart dependency not found under $CHART_PATH/charts" >&2
    exit 1
  fi

  helm template platform "$cert_manager_chart" \
    --namespace platform \
    --set crds.enabled=true \
    --show-only templates/crds.yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
  KUBECONFIG="$WL_KUBECONFIG" kubectl wait \
    --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=2m
fi

# The ingress-nginx admission cert jobs are Helm hooks. Re-running them on
# every server deploy makes the deploy path depend on a short-lived certgen
# Job even when ingress-nginx is already installed. Clean up a hook Job
# stranded by an interrupted/failed upgrade, then skip hooks only when the
# platform release and admission Secret already exist; fresh installs still
# run hooks so the Secret and webhook CA bundle are created normally.
KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform delete job \
  -l app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=admission-webhook \
  --ignore-not-found --cascade=foreground --timeout=2m || true

HELM_EXTRA_ARGS=()
if [ "$IS_KURA_REGIONAL_CLUSTER" = false ] &&
  KUBECONFIG="$WL_KUBECONFIG" helm status platform --namespace platform >/dev/null 2>&1 &&
  KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get secret platform-ingress-nginx-admission >/dev/null 2>&1; then
  HELM_EXTRA_ARGS+=(--no-hooks)
fi

# Dump platform-namespace state when helm exits non-zero. The caller's
# workflow-level diagnostics step targets the main tuist cluster, so a
# failure here would otherwise produce no actionable signal about the
# regional workload cluster (stuck certgen hook, image pull, RBAC, …).
dump_diagnostics() {
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    return 0
  fi
  echo "::group::platform install diagnostics ($CLUSTER_NAME)"
  echo "--- helm history platform ---"
  KUBECONFIG="$WL_KUBECONFIG" helm history platform -n platform --max 5 2>&1 || true
  echo "--- nodes ---"
  KUBECONFIG="$WL_KUBECONFIG" kubectl get nodes -o wide 2>&1 || true
  # Surface taints separately: kubectl get nodes -o wide hides taints, and
  # the most common reason for a stuck certgen hook is a Pending pod that
  # tolerates none of the taints on the cluster's only schedulable node
  # (e.g. a half-bootstrapped cluster with just the control-plane node).
  echo "--- node taints ---"
  KUBECONFIG="$WL_KUBECONFIG" kubectl get nodes \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}' 2>&1 || true
  echo "--- jobs in platform ns ---"
  KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get jobs -o wide 2>&1 || true
  echo "--- pods in platform ns ---"
  KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get pods -o wide 2>&1 || true
  echo "--- recent events (last 50) ---"
  KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get events \
    --sort-by=.lastTimestamp 2>&1 | tail -50 || true
  echo "--- ingress-nginx admission hook jobs ---"
  for job in $(KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get jobs \
    -l app.kubernetes.io/name=ingress-nginx -o name 2>/dev/null); do
    echo "--- describe $job ---"
    KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform describe "$job" 2>&1 || true
    for pod in $(KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get pods \
      -l "job-name=${job##*/}" -o name 2>/dev/null); do
      echo "--- describe $pod ---"
      KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform describe "$pod" 2>&1 || true
      echo "--- logs $pod ---"
      KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform logs "$pod" \
        --all-containers --tail=200 2>&1 || true
    done
  done
  echo "::endgroup::"
  return "$rc"
}
trap dump_diagnostics EXIT

HELM_CMD=(
  helm upgrade --install platform "$CHART_PATH"
  --namespace platform
  "${HELM_VALUES_ARGS[@]}"
  "${HELM_SET_ARGS[@]}"
)

if [ "${#HELM_EXTRA_ARGS[@]}" -gt 0 ]; then
  HELM_CMD+=("${HELM_EXTRA_ARGS[@]}")
fi

HELM_CMD+=(
  --wait
  --timeout "$HELM_TIMEOUT"
)

KUBECONFIG="$WL_KUBECONFIG" "${HELM_CMD[@]}"
