#!/usr/bin/env bash
#MISE description="Install or upgrade the Tuist platform chart (cert-manager, ESO, ingress-nginx, external-dns) on a workload cluster. Idempotent — safe to run on every deploy."
#USAGE arg "<kubeconfig>" help="Path to the workload cluster kubeconfig"
#USAGE arg "<cluster_name>" help="Cluster name, used for the ingress LoadBalancer Hetzner name and the external-dns owner ID (e.g. tuist-kura-us-east)"

# Brings a workload cluster to the desired state of the platform chart
# at HEAD: cert-manager + ClusterIssuer, ingress-nginx, external-dns,
# external-secrets. Designed to run from CI on every deploy so a
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

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ ! -r "$WL_KUBECONFIG" ]; then
  echo "ERROR: kubeconfig not readable: $WL_KUBECONFIG" >&2
  exit 1
fi

# HCCM stamps every node with topology.kubernetes.io/region (e.g. ash,
# hil, fsn1). Reading the location from the cluster keeps callers
# free of any region-name mapping that could drift from the actual
# placement.
REGION="$(KUBECONFIG="$WL_KUBECONFIG" kubectl get nodes \
  -o jsonpath='{.items[0].metadata.labels.topology\.kubernetes\.io/region}')"
if [ -z "$REGION" ]; then
  echo "ERROR: could not derive Hetzner location from topology.kubernetes.io/region on $WL_KUBECONFIG nodes" >&2
  exit 1
fi
log "Platform install for $CLUSTER_NAME (region $REGION)"

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
  --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/location=${REGION}"
  --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/name=${CLUSTER_NAME}-ingress"
)

# Sized for a cold cluster: ingress-nginx ships a pre-install admission
# Job whose image pull + cert generation, combined with the Hetzner LB
# provision for the controller Service, can take several minutes. 15m
# absorbs that with headroom; steady-state runs finish in under a
# minute and exit as soon as helm finds nothing to roll out.
HELM_TIMEOUT="15m"

# First-install ordering: our ClusterIssuer template depends on the
# cert-manager.io/v1 CRD that the cert-manager subchart ships. On a
# cluster that already has the CRD, a single pass is enough. On a
# fresh cluster we install the subcharts first with our ClusterIssuer
# disabled, wait for the CRD, then re-apply with it enabled — flipping
# clusterIssuer.enabled on a steady-state cluster would prune and
# re-create the resource, briefly blocking new cert issuance.
if KUBECONFIG="$WL_KUBECONFIG" kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
  KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install platform "$CHART_PATH" \
    --namespace platform \
    -f "$CHART_PATH/values-hetzner.yaml" \
    "${HELM_SET_ARGS[@]}" \
    --wait --timeout "$HELM_TIMEOUT"
else
  log "ClusterIssuer CRD missing; running two-pass install"
  KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install platform "$CHART_PATH" \
    --namespace platform \
    -f "$CHART_PATH/values-hetzner.yaml" \
    --set "clusterIssuer.enabled=false" \
    "${HELM_SET_ARGS[@]}" \
    --wait --timeout "$HELM_TIMEOUT"

  KUBECONFIG="$WL_KUBECONFIG" kubectl wait \
    --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=2m

  KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install platform "$CHART_PATH" \
    --namespace platform \
    -f "$CHART_PATH/values-hetzner.yaml" \
    "${HELM_SET_ARGS[@]}" \
    --wait --timeout "$HELM_TIMEOUT"
fi
