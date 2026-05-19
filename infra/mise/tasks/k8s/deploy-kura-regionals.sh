#!/usr/bin/env bash
#MISE description="Deploy the Kura regional platform/controller layer to the production us-east-1 and us-west-1 clusters."
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
KUBECONFIG_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/kura-kubeconfigs"
CLOUDFLARE_ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-tuist.dev}"

mkdir -p "$KUBECONFIG_DIR"
trap 'rm -rf "$KUBECONFIG_DIR"' EXIT

# Prefer a dedicated Kura/Cloudflare Load Balancing token when one is
# provided. The platform token is often limited to DNS-01 / external-dns
# scopes and cannot manage Cloudflare Load Balancers.
if [ -n "${KURA_CLOUDFLARE_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN="$KURA_CLOUDFLARE_API_TOKEN"
elif [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  CLOUDFLARE_API_TOKEN="$(op read "op://tuist-k8s-production/cloudflare-tuist-dns/credential")"
fi
export CLOUDFLARE_API_TOKEN

if [ -z "${CLOUDFLARE_ZONE_ID:-}" ] || [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  ZONE_RESPONSE="$(
    curl --fail --silent --show-error \
      --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      --header "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones?name=${CLOUDFLARE_ZONE_NAME}"
  )"

  if ! jq -e '.success == true and (.result | length) == 1' >/dev/null <<<"$ZONE_RESPONSE"; then
    echo "ERROR: could not resolve Cloudflare zone details for ${CLOUDFLARE_ZONE_NAME}" >&2
    jq -r '.errors // []' <<<"$ZONE_RESPONSE" >&2 || true
    exit 1
  fi

  export CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID:-$(jq -r '.result[0].id' <<<"$ZONE_RESPONSE")}"
  export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-$(jq -r '.result[0].account.id' <<<"$ZONE_RESPONSE")}"
fi

LB_RESPONSE="$(
  curl --fail --silent --show-error \
    --header "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    --header "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/load_balancers/pools?per_page=1"
)"

if ! jq -e '.success == true' >/dev/null <<<"$LB_RESPONSE"; then
  echo "ERROR: Cloudflare token cannot access Load Balancing APIs for account ${CLOUDFLARE_ACCOUNT_ID}." >&2
  echo "Set KURA_CLOUDFLARE_API_TOKEN to a token with Load Balancer permissions, or update the fallback token." >&2
  jq -r '.errors // []' <<<"$LB_RESPONSE" >&2 || true
  exit 1
fi

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

  KUBECONFIG="$kubeconfig" kubectl create namespace kura \
    --dry-run=client -o yaml | KUBECONFIG="$kubeconfig" kubectl apply -f -
  KUBECONFIG="$kubeconfig" kubectl -n kura create secret generic cloudflare-api-token \
    --from-literal=api-token="$CLOUDFLARE_API_TOKEN" \
    --dry-run=client -o yaml | KUBECONFIG="$kubeconfig" kubectl apply -f -

  KUBECONFIG="$kubeconfig" kubectl apply -f "$HELM_CHART_PATH/crds/"
  KUBECONFIG="$kubeconfig" helm upgrade --install "$HELM_RELEASE_NAME" "$HELM_CHART_PATH" \
    --namespace tuist-kura-controller --create-namespace \
    -f "$HELM_CHART_PATH/values-managed-kura-region.yaml" \
    --set kuraController.image.tag="$IMAGE_TAG" \
    --set kuraController.cloudflareLoadBalancing.enabled=true \
    --set kuraController.cloudflareLoadBalancing.accountID="$CLOUDFLARE_ACCOUNT_ID" \
    --set kuraController.cloudflareLoadBalancing.zoneID="$CLOUDFLARE_ZONE_ID" \
    --atomic --timeout 10m --wait
}

deploy_region "us-east-1" "tuist-kura-us-east" "kubeconfig: kura-us-east-1"
deploy_region "us-west-1" "tuist-kura-us-west" "kubeconfig: kura-us-west-1"
