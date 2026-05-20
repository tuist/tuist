#!/usr/bin/env bash
#MISE description="Deploy the Kura regional platform/controller/observability layer to the production us-east-1 and us-west-1 clusters."
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

deploy_region() {
  local region="$1"
  local cluster_name="$2"
  local kubeconfig_item="$3"
  local kubeconfig="$KUBECONFIG_DIR/${region}.yaml"

  op document get "$kubeconfig_item" \
    --vault "tuist-k8s-production" --output "$kubeconfig"
  chmod 600 "$kubeconfig"

  echo "Deploying Kura controller to $region"
  KUBECONFIG="$kubeconfig" kubectl --request-timeout=10s get --raw /version >/dev/null

  # Cluster names must match the CAPI Cluster CR names in
  # infra/k8s/clusters/cluster-production-us-{east,west}.yaml. They
  # drive external-dns.txtOwnerId and the Hetzner ingress LB annotation
  # set by k8s:install-platform, so drifting them would churn TXT
  # records and rename LBs on every deploy.
  mise -C "$REPO_ROOT/infra" run k8s:install-platform \
    "$kubeconfig" "$cluster_name"

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
    --atomic --timeout 10m --wait
}

deploy_region "us-east-1" "tuist-kura-us-east" "kubeconfig: kura-us-east-1"
deploy_region "us-west-1" "tuist-kura-us-west" "kubeconfig: kura-us-west-1"
