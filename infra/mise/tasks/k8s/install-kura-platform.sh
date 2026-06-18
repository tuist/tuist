#!/usr/bin/env bash
#MISE description="Install or upgrade the cluster-wide Kura controller in the `kura` namespace. Idempotent — every Slack-preview deploy runs this so the controller exists exactly once per cluster, regardless of how many ondemand previews coexist."
#USAGE arg "<kubeconfig>" help="Path to the workload cluster kubeconfig"

# Installs ONLY the kuraController resources from the tuist Helm chart into
# the `kura` namespace, using `helm template --show-only` so we don't have
# to install a full kuraController-only chart release (which would also
# render the server / data-plane templates that aren't gated on
# server.enabled). Resources are applied with `kubectl apply` and tracked
# via Helm-style labels for future GC.
#
# The kura-shared-secrets Secret is generated on first install with random
# clientId/clientSecret. Every subsequent run reuses the existing values so
# previously-issued cache tokens stay valid. Per-preview release wrappers
# (preview-ondemand-deploy.yml) copy this Secret into their own namespace
# so the server pod's `tuist.kuraIntrospectionEnv` helper resolves locally
# without cross-namespace secret references.

set -euo pipefail

WL_KUBECONFIG="$1"
REPO_ROOT="$(git rev-parse --show-toplevel)"
CHART_PATH="$REPO_ROOT/infra/helm/tuist"
KURA_NAMESPACE="kura"
KURA_CONTROLLER_IMAGE_TAG="${KURA_CONTROLLER_IMAGE_TAG:-latest}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ ! -r "$WL_KUBECONFIG" ]; then
  echo "ERROR: kubeconfig not readable: $WL_KUBECONFIG" >&2
  exit 1
fi

export KUBECONFIG="$WL_KUBECONFIG"

log "Resolving Kura introspection credentials"
kubectl get namespace "$KURA_NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$KURA_NAMESPACE"
CLIENT_ID="$(kubectl -n "$KURA_NAMESPACE" get secret kura-shared-secrets \
  -o jsonpath='{.data.KURA_CONTROL_PLANE_CLIENT_ID}' 2>/dev/null \
  | base64 -d 2>/dev/null || true)"
CLIENT_SECRET="$(kubectl -n "$KURA_NAMESPACE" get secret kura-shared-secrets \
  -o jsonpath='{.data.KURA_CONTROL_PLANE_CLIENT_SECRET}' 2>/dev/null \
  | base64 -d 2>/dev/null || true)"
if [ -z "$CLIENT_ID" ]; then
  CLIENT_ID="kura-platform-$(openssl rand -hex 4)"
fi
if [ -z "$CLIENT_SECRET" ]; then
  CLIENT_SECRET="$(openssl rand -hex 32)"
fi
echo "::add-mask::$CLIENT_SECRET"

log "Rendering Kura controller manifests for namespace=$KURA_NAMESPACE tag=$KURA_CONTROLLER_IMAGE_TAG"
helm template kura-platform "$CHART_PATH" \
  --namespace "$KURA_NAMESPACE" \
  --show-only templates/kura-controller.yaml \
  --set kuraController.enabled=true \
  --set "kuraController.namespace=$KURA_NAMESPACE" \
  --set "kuraController.image.tag=$KURA_CONTROLLER_IMAGE_TAG" \
  --set kuraController.sharedSecrets.enabled=true \
  --set kuraController.sharedSecrets.kuraIntrospection.enabled=true \
  --set-string "kuraController.sharedSecrets.kuraIntrospection.clientId=$CLIENT_ID" \
  --set-string "kuraController.sharedSecrets.kuraIntrospection.clientSecret=$CLIENT_SECRET" \
  | kubectl apply -f -

log "Waiting for Kura controller rollout"
kubectl -n "$KURA_NAMESPACE" rollout status deployment/kura-platform-tuist-kura-controller --timeout=3m

log "Kura platform installed in $KURA_NAMESPACE"
