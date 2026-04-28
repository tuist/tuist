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

# k8s tooling — installed via mise (platform-agnostic, no VM dependencies).
mise install kind@latest helm@latest kubectl@latest >/dev/null

# macOS VM stack. Brew ships colima + qemu, but lima needs to be pinned to v1.x:
# lima v2.0.3 / v2.1.1 (whatever brew currently has) consistently panic with
# `panic: send on closed channel` in pkg/driver/qemu/qemu_driver.go:382 the
# moment the qemu hostagent waits on the SSH requirement. v1 doesn't have the
# v2 rewrite of that driver and works.
if [[ "$(uname -s)" == "Darwin" ]] && ! docker info >/dev/null 2>&1; then
  for pkg in docker docker-compose colima qemu; do
    if ! brew list --formula "$pkg" >/dev/null 2>&1; then
      brew install "$pkg"
    fi
  done

  if ! command -v limactl >/dev/null 2>&1 || ! limactl --version | grep -q "limactl version 1\."; then
    echo "==> Installing pinned lima v1.2.1 (avoids the v2 qemu_driver panic)…"
    LIMA_VERSION="1.2.1"
    LIMA_ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/arm64/arm64/')
    curl -fsSL -o /tmp/lima.tar.gz \
      "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Darwin-${LIMA_ARCH}.tar.gz"
    sudo mkdir -p /opt/lima
    sudo tar -xzf /tmp/lima.tar.gz -C /opt/lima
    rm /tmp/lima.tar.gz
    PATH="/opt/lima/bin:$PATH"
    export PATH
  fi

  echo "==> Starting colima…"
  # Try vz first, fall back to qemu. With lima v1 even the qemu fallback is
  # safe (no panic).
  if ! colima start --vm-type vz --cpu 2 --memory 4 --disk 20; then
    echo "==> vz failed, retrying with qemu…"
    colima delete -f >/dev/null 2>&1 || true
    colima start --vm-type qemu --cpu 2 --memory 4 --disk 20
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not reachable after install + colima start." >&2
  exit 1
fi

if [[ -n "${GITHUB_ACTOR:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin >/dev/null
fi

echo "==> Pulling ${IMAGE_REF}…"
docker pull "$IMAGE_REF"

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
