#!/usr/bin/env bash
# MISE description="Bring up a per-shard kind cluster + tuist helm release for the CLI acceptance tests."
# MISE usage="<shard-index>"
#
# Mirrors `mise run helm:preview-up`'s kind + helm flow but trimmed for ephemeral CI:
#   * single-node kind cluster, no node pinning
#   * cache + redis disabled, observability off, ingress off
#   * port-forward backgrounded so the next workflow step can hit
#     http://localhost:${TUIST_CLUSTER_HOST_PORT} without a teardown step
#
# Each shard gets its own cluster name + host port so multiple invocations on the
# same Docker daemon don't fight over either:
#   * cluster name        → tuist-acceptance-${shard}
#   * TUIST_CLUSTER_HOST_PORT → 8080 + shard * 10
#
# License source — picked by which env var is exported (matches preview-up.sh):
#   $OP_SERVICE_ACCOUNT_TOKEN  → install External Secrets Operator + a 1Password
#                                ClusterSecretStore in the kind cluster. The
#                                chart's ExternalSecret pulls the license from
#                                item TUIST_LICENSE_KEY. CI uses this path —
#                                same shape Pedro's preview deploys use.
#   $TUIST_LICENSE_KEY         → local fallback. Skips ESO and inlines the key.
#                                Only for local development.
#
# Required env (one of):
#   OP_SERVICE_ACCOUNT_TOKEN  — 1Password service account token (CI path)
#   TUIST_LICENSE_KEY         — license key (local fallback)
# Required env (always):
#   TUIST_IMAGE_TAG           — image tag under ghcr.io/tuist/tuist (default: latest)
# Optional env (CI uses these to log in to GHCR before pulling):
#   GITHUB_ACTOR / GITHUB_TOKEN

set -euo pipefail

SHARD="${1:-0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HELM_CHART_DIR="$ROOT_DIR/infra/helm/tuist"

CLUSTER_NAME="tuist-acceptance-${SHARD}"
RELEASE_NAME="tuist"
NAMESPACE="tuist"
HOST_PORT="$((8080 + SHARD * 10))"
IMAGE_TAG="${TUIST_IMAGE_TAG:-latest}"
IMAGE_REF="ghcr.io/tuist/tuist:${IMAGE_TAG}"

if [[ -n "${OP_SERVICE_ACCOUNT_TOKEN:-}" ]]; then
  LICENSE_MODE="eso"
elif [[ -n "${TUIST_LICENSE_KEY:-}" ]]; then
  LICENSE_MODE="inline"
else
  echo "ERROR: set either OP_SERVICE_ACCOUNT_TOKEN (preferred, ESO path) or TUIST_LICENSE_KEY (local fallback)." >&2
  exit 1
fi
echo "==> License source: ${LICENSE_MODE}"

# Tools — installed on demand so a fresh runner doesn't need a separate
# `brew install` step. `lima` is colima's runtime (provides `limactl`); without
# it `colima start` exits with `limactl: executable file not found in $PATH`.
mise install kind@latest helm@latest kubectl@latest \
  colima@latest lima@latest docker-cli@latest >/dev/null

if [[ "$(uname -s)" == "Darwin" ]]; then
  # colima invokes `limactl` from PATH, so make lima's bin directory
  # discoverable for the duration of this script.
  PATH="$(mise where lima@latest)/bin:$PATH"
  export PATH
  if ! mise x colima@latest -- colima status >/dev/null 2>&1; then
    echo "==> Starting colima…"
    mise x colima@latest -- colima start --cpu 4 --memory 8 --disk 30
  fi
fi

if [[ -n "${GITHUB_ACTOR:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  echo "$GITHUB_TOKEN" | mise x docker-cli@latest -- docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin >/dev/null
fi

echo "==> Pulling ${IMAGE_REF}…"
mise x docker-cli@latest -- docker pull "$IMAGE_REF"

echo "==> Creating kind cluster '${CLUSTER_NAME}'…"
if ! mise x kind@latest -- kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  mise x kind@latest -- kind create cluster --name "$CLUSTER_NAME"
else
  echo "    Cluster '${CLUSTER_NAME}' already exists, reusing."
fi

echo "==> Loading ${IMAGE_REF} into the kind cluster…"
mise x kind@latest -- kind load docker-image "$IMAGE_REF" --name "$CLUSTER_NAME"

HELM_LICENSE_ARGS=()
if [[ "$LICENSE_MODE" = "eso" ]]; then
  echo "==> Installing External Secrets Operator…"
  mise x helm@latest -- helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
  mise x helm@latest -- helm repo update external-secrets >/dev/null
  mise x helm@latest -- helm upgrade --install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace \
    --set installCRDs=true \
    --wait --timeout 3m

  echo "==> Configuring 1Password ClusterSecretStore…"
  mise x kubectl@latest -- kubectl create namespace onepassword --dry-run=client -o yaml \
    | mise x kubectl@latest -- kubectl apply -f -
  mise x kubectl@latest -- kubectl -n onepassword delete secret onepassword-sa-token --ignore-not-found
  mise x kubectl@latest -- kubectl -n onepassword create secret generic onepassword-sa-token \
    --from-literal=token="$OP_SERVICE_ACCOUNT_TOKEN"

  cat <<'EOF' | mise x kubectl@latest -- kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: onepassword
spec:
  provider:
    onepasswordSDK:
      vault: tuist-k8s-preview
      auth:
        serviceAccountSecretRef:
          name: onepassword-sa-token
          namespace: onepassword
          key: token
EOF

  echo "==> Waiting for ClusterSecretStore to go Ready…"
  mise x kubectl@latest -- kubectl wait --for=condition=Ready clustersecretstore/onepassword --timeout=60s

  # values-acceptance.yaml already sets server.externalSecrets.license.item.
  # The ExternalSecret materialises a Secret the chart's app-secrets reads,
  # and helm --wait blocks on the migration job which transitively waits for it.
else
  echo "==> Local fallback: license will be inlined (no ESO)."
  HELM_LICENSE_ARGS=(
    --set "server.externalSecrets.license.item="
    --set "server.license.key=${TUIST_LICENSE_KEY}"
  )
fi

echo "==> Installing helm release '${RELEASE_NAME}' in namespace '${NAMESPACE}'…"
mise x kubectl@latest -- kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml \
  | mise x kubectl@latest -- kubectl apply -f -

mise x helm@latest -- helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_DIR" \
  --namespace "$NAMESPACE" \
  -f "$HELM_CHART_DIR/values-acceptance.yaml" \
  --set "server.image.repository=ghcr.io/tuist/tuist" \
  --set "server.image.tag=${IMAGE_TAG}" \
  --set "server.image.pullPolicy=Never" \
  --set "processor.image.repository=ghcr.io/tuist/tuist" \
  --set "processor.image.tag=${IMAGE_TAG}" \
  --set "processor.image.pullPolicy=Never" \
  --set "server.appUrl=http://localhost:${HOST_PORT}" \
  "${HELM_LICENSE_ARGS[@]}" \
  --wait --timeout 5m

echo "==> Seeding the test user (tuistrocks@tuist.dev)…"
SERVER_POD=$(mise x kubectl@latest -- kubectl get pods -n "$NAMESPACE" \
  -l app.kubernetes.io/component=server -o jsonpath='{.items[0].metadata.name}')
mise x kubectl@latest -- kubectl exec -n "$NAMESPACE" "$SERVER_POD" -- \
  /app/bin/tuist rpc 'Code.eval_file(Application.app_dir(:tuist, "priv/repo/seeds.exs"))'

echo "==> Forwarding cluster port 80 → localhost:${HOST_PORT}…"
PF_LOG="/tmp/tuist-acceptance-${SHARD}-port-forward.log"
PF_PID_FILE="/tmp/tuist-acceptance-${SHARD}-port-forward.pid"
nohup mise x kubectl@latest -- kubectl port-forward -n "$NAMESPACE" \
  "svc/${RELEASE_NAME}-server" "${HOST_PORT}:80" >"$PF_LOG" 2>&1 &
echo $! >"$PF_PID_FILE"
disown

# Give the forward a beat to bind, then sanity-check it.
sleep 2
if ! curl -fsS "http://localhost:${HOST_PORT}/ready" >/dev/null 2>&1; then
  echo "ERROR: port-forward did not come up. Log:" >&2
  cat "$PF_LOG" >&2
  exit 1
fi

echo "==> Cluster '${CLUSTER_NAME}' ready at http://localhost:${HOST_PORT}"
