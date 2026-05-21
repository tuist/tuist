#!/usr/bin/env bash
#MISE description="Provision the narrow steady-state CI deployer kubeconfig for an existing workload cluster."
#USAGE arg "<workload_kubeconfig>" help="Path to the workload cluster kubeconfig (admin / clusterctl-minted)"
#USAGE arg "<env>" help="Environment (staging | canary | production)"
#USAGE arg "[kubeconfig_item]" help="Optional 1Password document title (default: kubeconfig: tuist-<env>-deploy)"

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <workload_kubeconfig> <env> [kubeconfig_item]" >&2
  exit 64
fi

WL_KUBECONFIG="$1"
ENV="$2"
KUBECONFIG_ITEM="${3:-kubeconfig: tuist-${ENV}-deploy}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
TMP_KUBECONFIG="$(mktemp)"

case "$ENV" in
  staging|canary|production) ;;
  *) echo "ERROR: env must be one of staging|canary|production" >&2; exit 64 ;;
esac

case "$ENV" in
  production) APP_NAMESPACE="tuist" ;;
  *)          APP_NAMESPACE="tuist-${ENV}" ;;
esac

VAULT_NAME="tuist-k8s-${ENV}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
err() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; }

cleanup() {
  rm -f "$TMP_KUBECONFIG"
}
trap cleanup EXIT

require_resource() {
  local kind="$1"
  local name="$2"
  if ! KUBECONFIG="$WL_KUBECONFIG" kubectl get "$kind" "$name" >/dev/null 2>&1; then
    err "required resource $kind/$name is missing on the workload cluster"
    return 1
  fi
}

upload_document() {
  local file_path="$1"
  if op item get "$KUBECONFIG_ITEM" --account tuist.1password.com --vault "$VAULT_NAME" >/dev/null 2>&1; then
    local existing_id
    existing_id=$(op item get "$KUBECONFIG_ITEM" --account tuist.1password.com --vault "$VAULT_NAME" --format json | jq -r '.id')
    op item delete "$existing_id" --account tuist.1password.com --vault "$VAULT_NAME" --archive
  fi

  op document create "$file_path" \
    --title "$KUBECONFIG_ITEM" \
    --account tuist.1password.com --vault "$VAULT_NAME" >/dev/null
}

log "Validate workload state required by the narrow deployer"

require_resource crd kura.tuist.dev
require_resource crd runnerpools.tuist.dev
require_resource crd scalewayapplesiliconclusters.infrastructure.cluster.x-k8s.io
require_resource crd scalewayapplesiliconmachines.infrastructure.cluster.x-k8s.io
require_resource crd scalewayapplesiliconmachinetemplates.infrastructure.cluster.x-k8s.io
require_resource namespace "$APP_NAMESPACE"
require_resource namespace kura
require_resource namespace tailscale-operator
require_resource namespace tuist-runners
require_resource clusterrole tuist-tuist-capi-scaleway-applesilicon
require_resource clusterrole tuist-tuist-runners-controller
require_resource clusterrole tuist-tuist-runners-fleet-reader
require_resource clusterrole tuist-tuist-runners-token-reviewer
require_resource clusterrole tuist-tuist-tart-kubelet
require_resource clusterrolebinding tuist-tuist-capi-scaleway-applesilicon
require_resource clusterrolebinding tuist-tuist-runners-controller
require_resource clusterrolebinding tuist-tuist-runners-fleet-reader
require_resource clusterrolebinding tuist-tuist-runners-token-reviewer

log "Apply the narrow deployer RBAC"

sed "s/__APP_NAMESPACE__/${APP_NAMESPACE}/g" "$REPO_ROOT/infra/k8s/mgmt/ci-deployer-rbac.yaml" \
  | KUBECONFIG="$WL_KUBECONFIG" kubectl apply -f -

log "Mint the deployer kubeconfig"

SERVER=$(KUBECONFIG="$WL_KUBECONFIG" kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n "$APP_NAMESPACE" get secret github-actions-app-deployer-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(KUBECONFIG="$WL_KUBECONFIG" kubectl -n "$APP_NAMESPACE" get secret github-actions-app-deployer-token -o jsonpath='{.data.token}' | base64 -d)

cat > "$TMP_KUBECONFIG" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${ENV}
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA}
contexts:
  - name: deploy
    context:
      cluster: ${ENV}
      namespace: ${APP_NAMESPACE}
      user: github-actions-app-deployer
users:
  - name: github-actions-app-deployer
    user:
      token: ${TOKEN}
current-context: deploy
EOF

KUBECONFIG="$TMP_KUBECONFIG" kubectl -n "$APP_NAMESPACE" get deploy >/dev/null

log "Upload the deployer kubeconfig to 1Password"

upload_document "$TMP_KUBECONFIG"

cat <<DONE

Provisioned narrow deployer kubeconfig:
  Vault: ${VAULT_NAME}
  Item:  ${KUBECONFIG_ITEM}

The server deploy workflow will prefer this document for the main app Helm
upgrade and fall back to the admin kubeconfig when it is absent.
DONE
