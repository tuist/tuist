#!/usr/bin/env bash
# MISE description="Bring up a per-shard kind cluster + tuist helm release for the CLI acceptance tests."
# MISE usage="<shard-index>"
#
# Mirrors `mise run helm:preview-up`'s kind + helm flow but trimmed for ephemeral CI:
#   * single-node kind cluster, no node pinning
#   * cache + redis disabled, observability off, ingress off
#   * license sourced inline from $TUIST_LICENSE_KEY (no ESO bootstrap)
#   * port-forward backgrounded so the next workflow step can hit
#     http://localhost:${TUIST_CLUSTER_HOST_PORT} without a teardown step
#
# Each shard gets its own cluster name + host port so multiple invocations on the
# same Docker daemon don't fight over either:
#   * cluster name        → tuist-acceptance-${shard}
#   * TUIST_CLUSTER_HOST_PORT → 8080 + shard * 10
#
# Required env:
#   TUIST_IMAGE_TAG        — image tag under ghcr.io/tuist/tuist (default: latest)
#   TUIST_LICENSE_KEY      — license key for the server pod (required)
#
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

if [[ -z "${TUIST_LICENSE_KEY:-}" ]]; then
  echo "ERROR: TUIST_LICENSE_KEY must be set so the helm release can boot the server." >&2
  exit 1
fi

# Tools — installed on demand so a fresh runner doesn't need a separate
# `brew install` step. Skipped for tools the OS already provides.
mise install kind@latest helm@latest kubectl@latest \
  colima@latest docker-cli@latest >/dev/null

if [[ "$(uname -s)" == "Darwin" ]]; then
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
  --set "server.license.key=${TUIST_LICENSE_KEY}" \
  --set "server.appUrl=http://localhost:${HOST_PORT}" \
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
