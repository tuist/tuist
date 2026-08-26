#!/usr/bin/env bash
#MISE description="Install or upgrade the cluster-wide Kura controller in the `kura` namespace. Requires KURA_CONTROLLER_IMAGE_TAG."
#USAGE arg "<kubeconfig>" help="Path to the workload cluster kubeconfig"
#USAGE arg "[profile]" help="Controller placement and TLS profile (preview | pentest)" default="preview"

# Installs ONLY the kuraController resources from the tuist Helm chart into
# the `kura` namespace, using `helm template --show-only` so we don't have
# to install a full kuraController-only chart release (which would also
# render the server / data-plane templates that aren't gated on
# server.enabled). Resources are applied with `kubectl apply` and tracked
# via Helm-style labels for future GC.
#
# The kura-shared-secrets Secret is generated on first install with random
# clientId/clientSecret. Every subsequent run reuses the existing values so
# previously-issued cache tokens stay valid. A deployment can mirror the two
# control-plane keys into its application namespace when it needs local token
# introspection.

set -euo pipefail

WL_KUBECONFIG="$1"
PROFILE="${2:-preview}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
CHART_PATH="$REPO_ROOT/infra/helm/tuist"
KURA_NAMESPACE="kura"
KURA_CONTROLLER_IMAGE_TAG="${KURA_CONTROLLER_IMAGE_TAG:-}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [ -z "$KURA_CONTROLLER_IMAGE_TAG" ]; then
  echo "ERROR: KURA_CONTROLLER_IMAGE_TAG must be set to an immutable image tag." >&2
  exit 1
fi

if [ ! -r "$WL_KUBECONFIG" ]; then
  echo "ERROR: kubeconfig not readable: $WL_KUBECONFIG" >&2
  exit 1
fi

case "$PROFILE" in
  preview|pentest) ;;
  *)
    echo "ERROR: profile must be preview or pentest." >&2
    exit 64
    ;;
esac

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

log "Reconciling Kura custom resource definitions"
kubectl apply -f "$CHART_PATH/crds/"

log "Rendering Kura controller manifests for namespace=$KURA_NAMESPACE tag=$KURA_CONTROLLER_IMAGE_TAG profile=$PROFILE"
HELM_ARGS=(
  helm template kura-platform "$CHART_PATH"
  --namespace "$KURA_NAMESPACE" \
  --show-only templates/kura-controller.yaml \
  --set server.enabled=false \
  --set kuraController.enabled=true \
  --set "kuraController.namespace=$KURA_NAMESPACE" \
  --set "kuraController.image.tag=$KURA_CONTROLLER_IMAGE_TAG" \
  --set kuraController.sharedSecrets.enabled=true \
  --set kuraController.sharedSecrets.kuraIntrospection.enabled=true \
  --set-string "kuraController.sharedSecrets.kuraIntrospection.clientId=$CLIENT_ID" \
  --set-string "kuraController.sharedSecrets.kuraIntrospection.clientSecret=$CLIENT_SECRET"
)

if [ "$PROFILE" = "preview" ]; then
  # Every non-control-plane preview worker carries this taint.
  HELM_ARGS+=(
    --set "kuraController.tolerations[0].key=role"
    --set "kuraController.tolerations[0].operator=Equal"
    --set "kuraController.tolerations[0].value=preview"
    --set "kuraController.tolerations[0].effect=NoSchedule"
  )
else
  # The pentest controller must issue a certificate for its dedicated Kura
  # hostname. The issuer is installed by the cluster's platform chart.
  HELM_ARGS+=(--set kuraController.tlsClusterIssuer=letsencrypt-cloudflare)
fi

"${HELM_ARGS[@]}" | kubectl apply -f -

log "Waiting for Kura controller rollout"
kubectl -n "$KURA_NAMESPACE" rollout status deployment/kura-platform-tuist-kura-controller --timeout=3m

controller_restart_counts() {
  kubectl -n "$KURA_NAMESPACE" get pods \
    -l app.kubernetes.io/component=kura-controller \
    -o jsonpath='{range .items[*]}{.metadata.uid}{"="}{range .status.containerStatuses[*]}{.restartCount}{","}{end}{"\n"}{end}' \
    | sort
}

log "Verifying Kura controller stability"
restart_counts_before="$(controller_restart_counts)"
if [ -z "$restart_counts_before" ]; then
  echo "ERROR: Kura controller rollout completed without controller pods." >&2
  exit 1
fi
sleep 45
restart_counts_after="$(controller_restart_counts)"
if [ "$restart_counts_before" != "$restart_counts_after" ]; then
  echo "ERROR: Kura controller restarted after rollout." >&2
  exit 1
fi

log "Kura platform installed in $KURA_NAMESPACE"
