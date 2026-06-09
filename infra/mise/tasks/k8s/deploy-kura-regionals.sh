#!/usr/bin/env bash
#MISE description="Deploy the Kura regional platform/controller/observability layer to production regional clusters."
#USAGE arg "<image_tag>" help="Kura controller image tag to deploy"

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <image_tag>" >&2
  exit 64
fi

IMAGE_TAG="$1"
REPO_ROOT="$(git rev-parse --show-toplevel)"
HELM_CHART_PATH="$REPO_ROOT/infra/helm/tuist"
HELM_RELEASE_NAME="tuist"
MONITORING_CHART_PATH="$REPO_ROOT/infra/helm/k8s-monitoring"
KUBECONFIG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/kura-kubeconfigs"

mkdir -p "$KUBECONFIG_DIR"
trap 'rm -rf "$KUBECONFIG_DIR"' EXIT

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN="$(op read "op://tuist-k8s-production/cloudflare-tuist-dns/credential")"
fi
export CLOUDFLARE_API_TOKEN

helm dependency update "$MONITORING_CHART_PATH" >/dev/null

require_managed_secret_store() {
  local kubeconfig="$1"
  local cluster_name="$2"
  local kubeconfig_item="$3"

  if ! KUBECONFIG="$kubeconfig" kubectl get clustersecretstore onepassword >/dev/null 2>&1; then
    echo "ERROR: $cluster_name is missing ClusterSecretStore/onepassword required by managed ExternalSecrets." >&2
    echo "Install the onepassword ClusterSecretStore before deploying the Kura controller." >&2
    exit 1
  fi

  if ! KUBECONFIG="$kubeconfig" kubectl wait \
    --for=condition=Ready clustersecretstore/onepassword --timeout=2m >/dev/null; then
    echo "ERROR: $cluster_name ClusterSecretStore/onepassword is not Ready; managed ExternalSecrets will not reconcile." >&2
    echo "Fix the onepassword ClusterSecretStore before deploying the Kura controller." >&2
    exit 1
  fi
}

deploy_region() {
  local region="$1"
  local cluster_name="$2"
  local kubeconfig_item="$3"
  local provider="${4:-hetzner}"
  local kubeconfig="$KUBECONFIG_DIR/${region}.yaml"

  op document get "$kubeconfig_item" \
    --vault "tuist-k8s-production" --output "$kubeconfig"
  chmod 600 "$kubeconfig"

  echo "Deploying Kura controller to $region ($provider)"
  KUBECONFIG="$kubeconfig" kubectl --request-timeout=10s get --raw /version >/dev/null

  # Cluster names must match the CAPI Cluster CR names in
  # infra/k8s/clusters/cluster-production-us-{east,west}.yaml. They
  # drive external-dns.txtOwnerId, so drifting them would churn TXT
  # records on every deploy.
  mise -C "$REPO_ROOT/infra" run k8s:install-platform \
    "$kubeconfig" "$cluster_name" "$provider"

  # Monitoring and the Kura controller chart both resolve secrets through
  # ClusterSecretStore/onepassword. Gate on that contract instead of the
  # bootstrap implementation details behind it.
  require_managed_secret_store "$kubeconfig" "$cluster_name" "$kubeconfig_item"

  echo "Deploying Grafana monitoring to $region"
  KUBECONFIG="$kubeconfig" helm upgrade --install k8s-monitoring "$MONITORING_CHART_PATH" \
    --namespace observability --create-namespace \
    -f "$MONITORING_CHART_PATH/values-production.yaml" \
    --set "k8s-monitoring.cluster.name=$cluster_name" \
    --atomic --timeout 10m --wait

  KUBECONFIG="$kubeconfig" kubectl apply -f "$HELM_CHART_PATH/crds/"
  KUBECONFIG="$kubeconfig" helm upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_PATH" \
    --namespace tuist-kura-controller --create-namespace \
    -f "$HELM_CHART_PATH/values-managed-kura-region.yaml" \
    --set kuraController.image.tag="$IMAGE_TAG" \
    --set kuraController.loadBalancer.provider="$provider" \
    --atomic --timeout 10m --wait
}

deploy_region_if_kubeconfig_exists() {
  local region="$1"
  local cluster_name="$2"
  local kubeconfig_item="$3"
  local provider="${4:-hetzner}"

  if ! op item get "$kubeconfig_item" --vault "tuist-k8s-production" >/dev/null 2>&1; then
    echo "Skipping $region ($provider): 1Password document '$kubeconfig_item' does not exist yet"
    return
  fi

  deploy_region "$region" "$cluster_name" "$kubeconfig_item" "$provider"
}

deploy_extra_regions() {
  # Optional newline-separated rows for already-reconciled CAPI workload clusters:
  #   <cluster_id>|<cluster_name>|<1Password kubeconfig document>|<provider>
  # Example:
  #   au-southeast-1|tuist-kura-au-southeast|kubeconfig: kura-au-southeast-1|vultr
  if [ -z "${KURA_EXTRA_REGIONAL_DEPLOYMENTS:-}" ]; then
    return
  fi

  while IFS='|' read -r region cluster_name kubeconfig_item provider; do
    if [ -z "$region" ] || [[ "$region" == \#* ]]; then
      continue
    fi
    deploy_region "$region" "$cluster_name" "$kubeconfig_item" "${provider:-hetzner}"
  done <<< "$KURA_EXTRA_REGIONAL_DEPLOYMENTS"
}

deploy_region "us-east-1" "tuist-kura-us-east" "kubeconfig: kura-us-east-1" "hetzner"
deploy_region "us-west-1" "tuist-kura-us-west" "kubeconfig: kura-us-west-1" "hetzner"
deploy_region_if_kubeconfig_exists "au-southeast-1" "tuist-kura-au-southeast" "kubeconfig: kura-au-southeast-1" "vultr"
deploy_region_if_kubeconfig_exists "br-south-1" "tuist-kura-br-south" "kubeconfig: kura-br-south-1" "vultr"
deploy_extra_regions
