#!/usr/bin/env bash
#MISE description="Bootstrap a freshly-provisioned workload cluster end-to-end (CNI, CCM, CSI, platform, monitoring, and app bits when needed). Idempotent."
#USAGE arg "<cluster_name>" help="Cluster name (e.g. tuist-staging-2, tuist-canary, tuist, tuist-preview)"
#USAGE arg "<env>" help="Helm values overlay (staging | canary | production | preview)"
#USAGE arg "[kubeconfig_item]" help="Optional 1Password document title for the workload kubeconfig"

# End-to-end workload-cluster bootstrap. Run AFTER:
#   1. The Cluster CR is applied on the mgmt cluster, AND
#   2. ControlPlaneInitialized=True (kubeadm done, kubeconfig minted).
#
# What this does:
#   1. Extract the workload kubeconfig + API endpoint from the mgmt
#      cluster's ClusterCR + minted Secret.
#   2. Install Cilium (must be first — nothing networks without it).
#   3. Create the legacy `hetzner` Secret on the workload cluster and
#      wait for caph's `hcloud` Secret. HCCM + CSI read `hcloud`.
#   4. Install hcloud-cloud-controller-manager (sets providerID,
#      enables LoadBalancer Services).
#   5. Install hcloud-csi-driver (for parity; no PVCs use it today).
#   6. Wait for nodes to go Ready (CNI- and CCM-dependent).
#   7. Install the platform chart (cert-manager, ESO, external-dns,
#      metrics-server, and ingress-nginx only for app-serving clusters).
#   8. Install Cluster API core for the Mac mini fleet substrate.
#   9. Create the `onepassword` namespace + service-account-token
#      Secret + ClusterSecretStore so ESO can pull from 1Password.
#  10. Install the monitoring chart (Grafana Cloud agent).
#  11. App-serving clusters: pre-create the app namespace.
#  12. App-serving clusters: install the Cloudflare origin cert TLS Secret.
#  13. Smoke ingress + upload the workload kubeconfig to 1Password.
#
# Idempotent: re-running is safe; helm upgrades in-place, kubectl
# create | apply uses --dry-run + apply.

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <cluster_name> <env> [kubeconfig_item]" >&2
  echo "  cluster_name:     tuist-staging-2, tuist-canary, tuist, tuist-preview" >&2
  echo "  env:              staging | canary | production | preview" >&2
  echo "  kubeconfig_item:  optional 1Password document title, defaults to 'kubeconfig: tuist-<env>'" >&2
  exit 64
fi

CLUSTER_NAME="$1"
ENV="$2"
KUBECONFIG_ITEM="${3:-kubeconfig: tuist-${ENV}}"
NAMESPACE="${ORG_NAMESPACE:-org-tuist}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
BOOTSTRAP_DIR="$REPO_ROOT/infra/k8s/mgmt/bootstrap"
MGMT_KUBECONFIG="${MGMT_KUBECONFIG:-$HOME/.kube/tuist-mgmt.yaml}"
WL_KUBECONFIG="$HOME/.kube/${CLUSTER_NAME}.yaml"

case "$ENV" in
  staging|canary|production|preview) ;;
  *) echo "ERROR: env must be one of staging|canary|production|preview" >&2; exit 64 ;;
esac

# Map env -> 1Password vault name.
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

upload_workload_kubeconfig() {
  local kubeconfig_vault="tuist-k8s-${ENV}"

  if op item get "$KUBECONFIG_ITEM" --account tuist.1password.com --vault "$kubeconfig_vault" >/dev/null 2>&1; then
    local existing_id
    echo "Existing 1P item found; replacing the document"
    existing_id=$(op item get "$KUBECONFIG_ITEM" --account tuist.1password.com --vault "$kubeconfig_vault" --format json | jq -r '.id')
    op item delete "$existing_id" --account tuist.1password.com --vault "$kubeconfig_vault" --archive
  fi

  op document create "$WL_KUBECONFIG" \
    --title "$KUBECONFIG_ITEM" \
    --account tuist.1password.com --vault "$kubeconfig_vault"
}

# ---------------------------------------------------------------------------
log "Step 1/13: extract workload kubeconfig + API endpoint from mgmt"

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

CONTROL_PLANE_REPLICAS=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
  -o jsonpath='{.status.controlPlane.desiredReplicas}')
if [ -z "$CONTROL_PLANE_REPLICAS" ]; then
  CONTROL_PLANE_REPLICAS=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
    -o jsonpath='{.spec.topology.controlPlane.replicas}')
fi
CONTROL_PLANE_REPLICAS="${CONTROL_PLANE_REPLICAS:-1}"

WORKER_REPLICAS=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get cluster "$CLUSTER_NAME" \
  -o jsonpath='{.status.workers.desiredReplicas}')
if [ -z "$WORKER_REPLICAS" ]; then
  WORKER_REPLICAS=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get machinedeployments.cluster.x-k8s.io \
    -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" \
    -o jsonpath='{range .items[*]}{.spec.replicas}{"\n"}{end}' | awk '{sum += $1} END {print sum + 0}')
fi
WORKER_REPLICAS="${WORKER_REPLICAS:-0}"
EXPECTED_MACHINE_COUNT=$((CONTROL_PLANE_REPLICAS + WORKER_REPLICAS))

echo "API endpoint: ${API_HOST}:${API_PORT}"
echo "Region:       $REGION"
echo "Machines:     $EXPECTED_MACHINE_COUNT (${CONTROL_PLANE_REPLICAS} control plane, ${WORKER_REPLICAS} workers)"

# ---------------------------------------------------------------------------
log "Step 2/13: install Cilium (CNI must be first)"

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
log "Step 3/13: create workload Hetzner Secrets"

HCLOUD_TOKEN=$(op read --account tuist.1password.com "op://Founders/tuist-workloads/password")

# Older bootstrap wiring created kube-system/hetzner directly. Keep it
# idempotently present for compatibility, but HCCM and hcloud-csi consume
# kube-system/hcloud, which caph writes after the first control-plane node
# comes up.
KUBECONFIG="$WL_KUBECONFIG" kubectl -n kube-system create secret generic hetzner \
  --from-literal=hcloud="$HCLOUD_TOKEN" \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
unset HCLOUD_TOKEN

echo -n "Waiting for caph-provisioned kube-system/hcloud Secret"
HCLOUD_SECRET_TOKEN=""
for _ in $(seq 1 60); do
  HCLOUD_SECRET_TOKEN=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n kube-system get secret hcloud \
    -o jsonpath='{.data.token}' 2>/dev/null || true)
  if [ -n "$HCLOUD_SECRET_TOKEN" ]; then
    break
  fi
  printf '.'
  sleep 5
done
echo

if [ -z "$HCLOUD_SECRET_TOKEN" ]; then
  err "kube-system/hcloud Secret did not appear after 5 minutes. HCCM and hcloud-csi need it."
  err "Check caph reconciliation on the management cluster:"
  err "  KUBECONFIG=$MGMT_KUBECONFIG kubectl -n $NAMESPACE describe cluster $CLUSTER_NAME"
  exit 1
fi
unset HCLOUD_SECRET_TOKEN

# ---------------------------------------------------------------------------
log "Step 4/13: install hcloud-cloud-controller-manager"

helm repo add hcloud https://charts.hetzner.cloud >/dev/null 2>&1 || true
helm repo update hcloud >/dev/null

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install hccm hcloud/hcloud-cloud-controller-manager \
  --namespace kube-system \
  -f "$BOOTSTRAP_DIR/hccm-values.yaml" \
  --set "env.HCLOUD_LOAD_BALANCERS_LOCATION.value=${REGION}" \
  --wait --timeout 3m

# ---------------------------------------------------------------------------
log "Step 5/13: install hcloud-csi-driver"

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install hcloud-csi hcloud/hcloud-csi \
  --namespace kube-system \
  -f "$BOOTSTRAP_DIR/hcloud-csi-values.yaml" \
  --wait --timeout 3m

# ---------------------------------------------------------------------------
log "Step 6/13: wait for CAPI machines and workload nodes to go Ready"

echo -n "Waiting for $EXPECTED_MACHINE_COUNT CAPI Machines to exist"
MACHINE_COUNT=0
for _ in $(seq 1 120); do
  MACHINE_COUNT=$(KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get machines.cluster.x-k8s.io \
    -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$MACHINE_COUNT" -ge "$EXPECTED_MACHINE_COUNT" ]; then
    break
  fi
  printf '.'
  sleep 5
done
echo

if [ "$MACHINE_COUNT" -lt "$EXPECTED_MACHINE_COUNT" ]; then
  err "Only $MACHINE_COUNT/$EXPECTED_MACHINE_COUNT CAPI Machines exist for $CLUSTER_NAME."
  KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get machines.cluster.x-k8s.io \
    -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" -o wide >&2 || true
  exit 1
fi

if ! KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" wait --for=condition=Ready \
  machines.cluster.x-k8s.io -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" --timeout=20m; then
  err "Not all CAPI Machines for $CLUSTER_NAME became Ready."
  KUBECONFIG="$MGMT_KUBECONFIG" kubectl -n "$NAMESPACE" get machines.cluster.x-k8s.io,hcloudmachines.infrastructure.cluster.x-k8s.io \
    -l "cluster.x-k8s.io/cluster-name=$CLUSTER_NAME" -o wide >&2 || true
  exit 1
fi

KUBECONFIG="$WL_KUBECONFIG" kubectl wait --for=condition=Ready nodes --all --timeout=5m

# ---------------------------------------------------------------------------
log "Step 7/13: install shared platform chart"

# `mise -C "$REPO_ROOT/infra"` so the nested task resolves regardless
# of where the caller ran bootstrap-workload from; k8s:* tasks live in
# infra/mise.toml scope, not the repo root.
mise -C "$REPO_ROOT/infra" run k8s:install-platform "$WL_KUBECONFIG" "$CLUSTER_NAME"

# ---------------------------------------------------------------------------
log "Step 8/13: install Cluster API core (Mac mini fleet substrate)"

# The Tuist helm chart renders nested CAPI CRs (Cluster +
# MachineDeployment + Machine + ScalewayAppleSilicon{Cluster,Machine,MachineTemplate})
# into the workload cluster to manage Mac mini fleets via the
# `capi-provider-scaleway-applesilicon` infra provider that the
# chart itself deploys. CAPI core (the controllers behind those
# CRDs) ships outside the chart and is installed once per
# workload cluster.
#
# We use clusterctl rather than `kubectl apply` of the raw
# core-components.yaml because the manifest carries shell-style
# `${VAR:=default}` placeholders that kubectl stores verbatim,
# leaving the controller binary to bail out on
# `invalid argument "${CAPI_INSECURE_DIAGNOSTICS:=false}"`.
#
# Why this lives in bootstrap, not in CI: CAPI install is a
# one-time per-cluster concern, not per-deploy. Running
# `clusterctl init` on every server-deployment was a
# self-healing belt-and-suspenders that mostly burned ~10-30s
# of CI time on no-ops — and on a fresh cluster where it
# actually did work, the work belongs here next to the rest
# of the cluster's day-zero setup.
#
# Cert-manager is a hard dep (CAPI webhooks need
# cert-issued certs). Platform install in step 7 brought it
# up, so we're good to install here.

CAPI_CORE_VERSION="v1.10.4"
CLUSTERCTL_BIN="$RUNNER_TEMP/clusterctl"

if [ -z "${RUNNER_TEMP:-}" ]; then
  CLUSTERCTL_BIN="${TMPDIR:-/tmp}/clusterctl"
fi

if [ ! -x "$CLUSTERCTL_BIN" ]; then
  log "  Downloading clusterctl ${CAPI_CORE_VERSION}"
  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64|aarch64) CLUSTERCTL_ARCH="arm64" ;;
    x86_64|amd64)  CLUSTERCTL_ARCH="amd64" ;;
    *) err "Unsupported arch for clusterctl: $ARCH"; exit 1 ;;
  esac
  OS_KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')"
  curl -fsSL -o "$CLUSTERCTL_BIN" \
    "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPI_CORE_VERSION}/clusterctl-${OS_KERNEL}-${CLUSTERCTL_ARCH}"
  chmod +x "$CLUSTERCTL_BIN"
fi

# `clusterctl init` is idempotent on a per-provider basis: it
# exits non-zero with "already initialized" if the provider is
# present at the same version. We swallow the exit and verify
# the deployment is Available afterwards rather than parsing
# the error text.
KUBECONFIG="$WL_KUBECONFIG" "$CLUSTERCTL_BIN" init --core "cluster-api:${CAPI_CORE_VERSION}" 2>/dev/null || true

# 10 min budget: cert-manager has to issue the webhook serving
# cert, the controller image pulls from registry.k8s.io. A cold
# install easily eats 5+ min.
KUBECONFIG="$WL_KUBECONFIG" kubectl -n capi-system wait \
  --for=condition=Available deploy/capi-controller-manager --timeout=10m

# ---------------------------------------------------------------------------
log "Step 9/13: wire ESO -> 1Password for the per-env vault"

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
log "Step 10/13: install monitoring chart"

helm dependency update "$REPO_ROOT/infra/helm/k8s-monitoring" >/dev/null

KUBECONFIG="$WL_KUBECONFIG" kubectl create namespace observability --dry-run=client -o yaml | \
  KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

MONITORING_VALUES_FILE="$REPO_ROOT/infra/helm/k8s-monitoring/values-${ENV}.yaml"

KUBECONFIG="$WL_KUBECONFIG" helm upgrade --install k8s-monitoring "$REPO_ROOT/infra/helm/k8s-monitoring" \
  --namespace observability \
  -f "$MONITORING_VALUES_FILE" \
  --wait --timeout 5m || echo "WARN: monitoring chart didn't go Ready in 5min; continuing (not blocking the cluster)"

# ---------------------------------------------------------------------------
log "Step 11/13: pre-create the app namespace (CI deploys the app itself)"

# The bootstrap script intentionally does NOT install the tuist app
# chart. Real Tuist server deploys go through `server-deployment.yml`
# in CI: it builds the server image tagged by commit SHA, pushes to
# ghcr.io, then `helm upgrade --set image.tag=<sha>`. The chart's
# `appVersion` is a placeholder, not a real image with the encrypted
# secrets file baked in — installing it from here would just produce
# a CrashLoopBackOff.
#
# We only pre-create the namespace + the ESO-synced server-master-key
# Secret (already wired by the platform / common values) so CI's
# first deploy doesn't have to bootstrap its own namespace.
# Production's Cluster CR uses metadata.name=tuist (no -production
# suffix); the namespace mirrors that.
case "$ENV" in
  production) APP_NAMESPACE="tuist" ;;
  *)          APP_NAMESPACE="tuist-${ENV}" ;;
esac
KUBECONFIG="$WL_KUBECONFIG" kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | \
  KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

# ---------------------------------------------------------------------------
log "Step 12/13: install Cloudflare origin cert as TLS Secret"

# Cloudflare-proxied DNS (the orange cloud) requires the origin to
# present a Cloudflare Origin Certificate to satisfy "Full (strict)"
# SSL mode. The cert is a wildcard *.tuist.dev with 15-year validity,
# stored in 1Password Founders/cloudflare-origin-cert-tuist-dev.
# The chart's Ingress references `tlsSecretName:
# tuist-tls-cloudflare-origin` in the app namespace.
#
# Gotcha worth knowing: the private_key field in 1Password has stray
# blank lines after the BEGIN/END markers (likely a 1P data quirk for
# multi-line Concealed values). openssl + ingress-nginx both reject
# such PEMs as malformed. We strip those before building the Secret.
CERT_TMP=$(mktemp); KEY_TMP=$(mktemp)
op read --account tuist.1password.com \
  "op://Founders/cloudflare-origin-cert-tuist-dev/certificate" > "$CERT_TMP"
op read --account tuist.1password.com \
  "op://Founders/cloudflare-origin-cert-tuist-dev/private_key" > "$KEY_TMP"
sed -i.bak '/^[[:space:]]*$/d' "$CERT_TMP" "$KEY_TMP" && rm -f "${CERT_TMP}.bak" "${KEY_TMP}.bak"
# Sanity: the cert and key must match.
CERT_MOD=$(openssl x509 -noout -modulus < "$CERT_TMP" 2>/dev/null | openssl md5)
KEY_MOD=$(openssl rsa -noout -modulus < "$KEY_TMP" 2>/dev/null | openssl md5)
if [ "$CERT_MOD" != "$KEY_MOD" ]; then
  err "Cloudflare origin cert + key modulus mismatch — refusing to create the Secret"
  rm -f "$CERT_TMP" "$KEY_TMP"
  exit 1
fi
KUBECONFIG="$WL_KUBECONFIG" kubectl -n "$APP_NAMESPACE" create secret tls tuist-tls-cloudflare-origin \
  --cert="$CERT_TMP" --key="$KEY_TMP" \
  --dry-run=client -o yaml | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -
rm -f "$CERT_TMP" "$KEY_TMP"

# ---------------------------------------------------------------------------
log "Step 13/13: smoke ingress + upload workload kubeconfig to 1Password"

# Wait for HCCM to provision the LB and write the IP back.
echo -n "Waiting for ingress-nginx LB IP"
for i in $(seq 1 60); do
  LB_IP=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n platform get svc platform-ingress-nginx-controller \
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

# Smoke: the ingress LB actually serves HTTP. Any non-zero status (including
# 404 from ingress-nginx's default backend) proves the full path
# Hetzner-LB -> Service -> ingress-nginx pod is wired. Connection failures
# here mean the cluster is structurally incomplete despite earlier helm
# successes, and uploading the kubeconfig to 1P would hand CI a target
# that can't actually serve traffic.
echo -n "Probing https://$LB_IP/ "
SMOKE_HTTP=000
for i in $(seq 1 30); do
  SMOKE_HTTP=$(curl -sS -k --connect-timeout 5 --max-time 10 \
    -o /dev/null -w "%{http_code}" "https://$LB_IP/" 2>/dev/null || echo "000")
  if [ "$SMOKE_HTTP" != "000" ]; then
    break
  fi
  printf '.'
  sleep 5
done
echo

if [ "$SMOKE_HTTP" = "000" ]; then
  err "ingress LB $LB_IP did not return HTTP after ~2.5min, refusing to publish kubeconfig to 1P."
  err "The cluster looks structurally incomplete. Investigate:"
  err "  KUBECONFIG=$WL_KUBECONFIG kubectl -n platform get svc,pods -l app.kubernetes.io/name=ingress-nginx"
  exit 1
fi
echo "ingress LB responded HTTP $SMOKE_HTTP. Routing is healthy."

# Stash the freshly-minted workload kubeconfig in the per-env vault
# so CI (server-deployment.yml) can read it via the per-env
# OP_SERVICE_ACCOUNT_TOKEN. Only runs after the smoke above passes, so
# a stale kubeconfig never overwrites a working one when bootstrap is
# invoked against a half-built cluster.
# By default, app cluster document names follow env, not cluster_name,
# so the deploy workflow can look up `kubeconfig: tuist-${env}`
# uniformly across all environments.
upload_workload_kubeconfig

echo

cat <<DONE

================================================================
Bootstrap of $CLUSTER_NAME complete.

  Workload kubeconfig: $WL_KUBECONFIG
  Ingress LB IP:       $LB_IP

Domain cut: in Cloudflare, update the relevant alias or address records
to point at $LB_IP.

  staging   -> staging.tuist.dev
  canary    -> canary.tuist.dev
  production -> tuist.dev (and any apex aliases)
  preview   -> ExternalDNS reconciles *.preview.tuist.dev from the ingress Service

Verify the certificate and ingress on the new cluster (domain cut not needed for this):
  curl -k --resolve "staging.tuist.dev:443:$LB_IP" https://staging.tuist.dev/health
================================================================
DONE
