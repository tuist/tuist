#!/usr/bin/env bash
#MISE description="Bootstrap a freshly-provisioned workload cluster end-to-end (CNI, CCM, CSI, platform, monitoring, app). Idempotent."
#USAGE arg "<cluster_name>" help="Cluster name (e.g. tuist-staging-2, tuist-canary, tuist, tuist-preview)"
#USAGE arg "<env>" help="Helm values overlay (staging | canary | production | preview)"

# End-to-end workload-cluster bootstrap. Run AFTER:
#   1. The Cluster CR is applied on the mgmt cluster, AND
#   2. ControlPlaneInitialized=True (kubeadm done, kubeconfig minted).
#
# What this does:
#   1. Extract the workload kubeconfig + API endpoint from the mgmt
#      cluster's ClusterCR + minted Secret.
#   2. Install Cilium (must be first — nothing networks without it).
#   3. Install hcloud-cloud-controller-manager (sets providerID,
#      enables LoadBalancer Services).
#   4. Install hcloud-csi-driver (for parity; no PVCs use it today).
#   5. Wait for nodes to go Ready (CNI- and CCM-dependent).
#   6. Create the `hetzner` Secret on the workload cluster (same
#      project token as the mgmt-side Secret; HCCM + CSI both read it).
#   7. Create the `onepassword` namespace + service-account-token
#      Secret + ClusterSecretStore so ESO can pull from 1Password.
#   8. Install the platform chart (cert-manager, ESO, ingress-nginx,
#      external-dns).
#   9. Install the monitoring chart (Grafana Cloud agent).
#  10. Install the tuist app chart with the env-specific values.
#  11. Print the externally-routable LB IP for DNS cut.
#
# Idempotent: re-running is safe; helm upgrades in-place, kubectl
# create | apply uses --dry-run + apply.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <cluster_name> <env>" >&2
  echo "  cluster_name: tuist-staging-2, tuist-canary, tuist, tuist-preview" >&2
  echo "  env:          staging | canary | production | preview" >&2
  exit 64
fi

CLUSTER_NAME="$1"
ENV="$2"
NAMESPACE="${ORG_NAMESPACE:-org-tuist}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
BOOTSTRAP_DIR="$REPO_ROOT/infra/k8s/mgmt/bootstrap"
MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-$HOME/.kube/tuist-mgmt.yaml}"
WL_KUBECONFIG="$HOME/.kube/${CLUSTER_NAME}.yaml"

case "$ENV" in
  staging|canary|production|preview) ;;
  *) echo "ERROR: env must be one of staging|canary|production|preview" >&2; exit 64 ;;
esac

# Map env -> 1Password vault name. Keep aligned with existing Apalla
# clusters' ClusterSecretStore configs.
case "$ENV" in
  staging)    VAULT_NAME="tuist-k8s-staging"    ;  OP_TOKEN_ID="4yaimkh5gcxwopssmkod5er2fm" ;;
  canary)     VAULT_NAME="tuist-k8s-canary"     ;  OP_TOKEN_ID="6o5lcwgudi6qtt2754svzh7jka" ;;
  production) VAULT_NAME="tuist-k8s-production" ;  OP_TOKEN_ID="gunhzznxo73w2p3hy6t46nihym" ;;
  preview)    VAULT_NAME="tuist-k8s-preview"    ;  OP_TOKEN_ID="skxlwhsvmnqqvrmiqzlxs7fqru" ;;
esac
# OP_TOKEN_ID points at the per-env "Service Account Auth Token: tuist-<env>-k8s"
# 1P item, addressed by UUID because the colon in the title trips up `op read`.

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
err() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; }

# ---------------------------------------------------------------------------
log "Step 1/11: extract workload kubeconfig + API endpoint from mgmt"

if ! KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" >/dev/null 2>&1; then
  err "Cluster $NAMESPACE/$CLUSTER_NAME not found on mgmt cluster ($MGMT_KUBECONFIG). Apply the Cluster CR first."
  exit 1
fi

CP_INITIALIZED=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
  -o jsonpath='{.status.conditions[?(@.type=="ControlPlaneInitialized")].status}')
if [ "$CP_INITIALIZED" != "True" ]; then
  err "Cluster $CLUSTER_NAME is not yet ControlPlaneInitialized. Wait and retry."
  exit 1
fi

# Mint workload kubeconfig.
clusterctl get kubeconfig "$CLUSTER_NAME" -n "$NAMESPACE" \
  --kubeconfig="$MGMT_KUBECONFIG" > "$WL_KUBECONFIG"
chmod 600 "$WL_KUBECONFIG"
echo "Wrote workload kubeconfig: $WL_KUBECONFIG"

API_HOST=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
  -o jsonpath='{.spec.controlPlaneEndpoint.host}')
API_PORT=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
  -o jsonpath='{.spec.controlPlaneEndpoint.port}')
REGION=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
  -o jsonpath='{.spec.topology.variables[?(@.name=="region")].value}' | tr -d '"')
REGION="${REGION:-fsn1}"

echo "API endpoint: ${API_HOST}:${API_PORT}"
echo "Region:       $REGION"

# ---------------------------------------------------------------------------
log "Step 2/11: install Cilium (CNI must be first)"

# Repo add is idempotent.
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install cilium cilium/cilium \
  --version 1.18.7 \
  --namespace kube-system \
  -f "$BOOTSTRAP_DIR/cilium-values.yaml" \
  --set "k8sServiceHost=${API_HOST}" \
  --set "k8sServicePort=${API_PORT}"
# Don't --wait here: hubble-relay (a Deployment) can't schedule
# until at least one non-CP node is Ready, and that doesn't happen
# until HCCM is installed below. The cilium-agent DaemonSet installs
# on each node as the node registers, no wait needed; later steps
# only depend on the agent, not hubble-relay.

# ---------------------------------------------------------------------------
log "Step 3/11: create hetzner Secret on workload (HCCM + CSI both read it)"

HCLOUD_TOKEN=$(op read --account tuist.1password.com "op://Founders/tuist-workloads/password")

KUBECONFIG="$WL_KUBECONFIG" kubectl -n kube-system create secret generic hetzner \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
unset HCLOUD_TOKEN

# ---------------------------------------------------------------------------
log "Step 4/11: install hcloud-cloud-controller-manager"

helm repo add hcloud https://charts.hetzner.cloud >/dev/null 2>&1 || true
helm repo update hcloud >/dev/null

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
  --namespace kube-system \
  -f "$BOOTSTRAP_DIR/hccm-values.yaml" \
  --set "env.HCLOUD_LOAD_BALANCERS_LOCATION.value=${REGION}" \
  --wait --timeout 3m

# ---------------------------------------------------------------------------
log "Step 5/11: install hcloud-csi-driver"

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install hcloud-csi hcloud/hcloud-csi \
  --namespace kube-system \
  -f "$BOOTSTRAP_DIR/hcloud-csi-values.yaml" \
  --wait --timeout 3m

# ---------------------------------------------------------------------------
log "Step 6/11: wait for nodes to go Ready"

KUBECONFIG="$WL_KUBECONFIG" kubectl wait --for=condition=Ready nodes --all --timeout=5m

# ---------------------------------------------------------------------------
log "Step 7/11: install platform chart (cert-manager, ESO, ingress-nginx)"

helm dependency update "$REPO_ROOT/infra/helm/platform" >/dev/null

# Cloudflare API token for cert-manager DNS-01 challenge.
CF_TOKEN=$(op read --account tuist.1password.com "op://Founders/cloudflare-tuist-dns/credential")

KUBECONFIG="$WL_KUBECONFIG" kubectl create namespace platform --dry-run=client -o yaml | \
  KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform create secret generic cloudflare-api-token \
  --from-literal=api-token="$CF_TOKEN" \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
unset CF_TOKEN

# Two-step install: cert-manager's ClusterIssuer CRD is templated as
# part of the cert-manager subchart, so it's registered alongside
# our ClusterIssuer template — helm rejects that race with
# "no matches for kind ClusterIssuer in version cert-manager.io/v1".
# Step 7a: install everything EXCEPT our ClusterIssuer; cert-manager
# subchart applies its CRDs.
# Step 7b: re-apply with the ClusterIssuer enabled (default).
KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install platform "$REPO_ROOT/infra/helm/platform" \
  --namespace platform \
  -f "$REPO_ROOT/infra/helm/platform/values-hetzner.yaml" \
  --set "clusterIssuer.enabled=false" \
  --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/location=${REGION}" \
  --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/name=${CLUSTER_NAME}-ingress" \
  --wait --timeout 5m

KUBECONFIG="$WL_KUBECONFIG" kubectl wait --for=condition=Established crd/clusterissuers.cert-manager.io --timeout=2m

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install platform "$REPO_ROOT/infra/helm/platform" \
  --namespace platform \
  -f "$REPO_ROOT/infra/helm/platform/values-hetzner.yaml" \
  --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/location=${REGION}" \
  --set "ingress-nginx.controller.service.annotations.load-balancer\.hetzner\.cloud/name=${CLUSTER_NAME}-ingress" \
  --wait --timeout 5m

# ---------------------------------------------------------------------------
log "Step 8/11: wire ESO -> 1Password for the per-env vault"

OP_TOKEN=$(op read --account tuist.1password.com "op://Founders/${OP_TOKEN_ID}/credential")

# Wait for ESO's ClusterSecretStore CRD to be Established. The platform
# chart installs ESO and its CRDs are registered through the chart's
# templates rather than `crds/`, so they may not be visible to kubectl
# apply immediately even though `helm upgrade --wait` returned.
KUBECONFIG="$WL_KUBECONFIG" kubectl wait --for=condition=Established \
  crd/clustersecretstores.external-secrets.io --timeout=2m

# Apply namespace + ClusterSecretStore (vault name templated).
VAULT_NAME="$VAULT_NAME" envsubst < "$BOOTSTRAP_DIR/onepassword-secretstore.yaml" | \
  KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

KUBECONFIG="$WL_KUBECONFIG" kubectl -n onepassword create secret generic onepassword-sa-token \
  --from-literal=token="$OP_TOKEN" \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
unset OP_TOKEN

# Wait for the ClusterSecretStore to validate.
KUBECONFIG="$WL_KUBECONFIG" kubectl wait --for=condition=Ready clustersecretstore/onepassword --timeout=2m

# ---------------------------------------------------------------------------
log "Step 9/11: install monitoring chart"

helm dependency update "$REPO_ROOT/infra/helm/k8s-monitoring" >/dev/null

KUBECONFIG="$WL_KUBECONFIG" kubectl create namespace observability --dry-run=client -o yaml | \
  KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install k8s-monitoring "$REPO_ROOT/infra/helm/k8s-monitoring" \
  --namespace observability \
  -f "$REPO_ROOT/infra/helm/k8s-monitoring/values-${ENV}.yaml" \
  --wait --timeout 5m || echo "WARN: monitoring chart didn't go Ready in 5min; continuing (not blocking the cluster)"

# ---------------------------------------------------------------------------
log "Step 10/11: install the tuist app chart"

# tuist-staging is the namespace the existing chart expects.
APP_NAMESPACE="tuist-${ENV}"
KUBECONFIG="$WL_KUBECONFIG" kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | \
  KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

helm dependency update "$REPO_ROOT/infra/helm/tuist" >/dev/null

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install tuist "$REPO_ROOT/infra/helm/tuist" \
  --namespace "$APP_NAMESPACE" \
  -f "$REPO_ROOT/infra/helm/tuist/values-managed-common.yaml" \
  -f "$REPO_ROOT/infra/helm/tuist/values-managed-${ENV}.yaml" \
  --wait --timeout 10m

# ---------------------------------------------------------------------------
log "Step 11/11: report ingress LB IP (DNS cut target)"

# Wait for HCCM to provision the LB and write the IP back.
for i in $(seq 1 60); do
  LB_IP=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$LB_IP" ]; then
    break
  fi
  printf '.'
  sleep 5
done
echo

if [ -z "${LB_IP:-}" ]; then
  err "ingress-nginx Service has no LoadBalancer IP after 5 minutes. Check HCCM logs:"
  err "  KUBECONFIG=$WL_KUBECONFIG kubectl -n kube-system logs -l app.kubernetes.io/name=hcloud-cloud-controller-manager"
  exit 1
fi

cat <<DONE

================================================================
Bootstrap of $CLUSTER_NAME complete.

  Workload kubeconfig: $WL_KUBECONFIG
  Ingress LB IP:       $LB_IP

DNS cut: in Cloudflare, update the relevant CNAME / A record(s)
to point at $LB_IP.

  staging   -> staging.tuist.dev
  canary    -> canary.tuist.dev
  production -> tuist.dev (and any apex aliases)
  preview   -> *.preview.tuist.dev (or whatever wildcard pattern is used)

Verify cert + ingress on the new cluster (DNS cut not needed for this):
  curl -k --resolve "staging.tuist.dev:443:$LB_IP" https://staging.tuist.dev/health
================================================================
DONE
