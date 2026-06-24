#!/usr/bin/env bash
#MISE description="Prep a pre-ordered OVH box (install Ubuntu + the fleet key) so the fleet self-joins it"
#
# Adoption is now a fast self-join, so a box must be prepared before its adoption
# displayName is set. This installs Ubuntu with the fleet's SSH key so the
# controller can self-join it on the next claim — no hand-installing.
#
# Usage:
#   mise run baremetal:prep-ovh <service-name> [fleet-name]
#   e.g. mise run baremetal:prep-ovh ns543284.ip-144-217-252.net
#
# Reads the fleet pubkey from the operator-minted <fleet>-ssh Secret (so the fleet
# must be deployed first) and the OVH_API triple from 1Password. OVH_API_BASE
# selects the entity (default ovh-us). Override the cluster via PREP_KUBE_CONTEXT /
# PREP_NAMESPACE, or the creds via env.

set -euo pipefail

service="${1:-}"
fleet="${2:-tuist-tuist-ovh-fleet}"
ns="${PREP_NAMESPACE:-tuist-staging}"

if [ -z "$service" ]; then
  echo "usage: mise run baremetal:prep-ovh <service-name> [fleet-name]" >&2
  echo "  e.g. mise run baremetal:prep-ovh ns543284.ip-144-217-252.net" >&2
  exit 2
fi

kube=(kubectl)
[ -n "${PREP_KUBE_CONTEXT:-}" ] && kube=(kubectl --context "$PREP_KUBE_CONTEXT")

pubkey="$("${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.id_ed25519\.pub}' 2>/dev/null | base64 -d || true)"
[ -z "$pubkey" ] && { echo "no id_ed25519.pub in secret ${fleet}-ssh (-n $ns); is the fleet deployed and the key minted?" >&2; exit 1; }

# go-ovh reads these from the env. OVH_ENDPOINT must match the box's entity (the
# token is bound to it); the BHS staging box is on an OVHcloud US account.
export OVH_ENDPOINT="${OVH_ENDPOINT:-ovh-us}"
export OVH_APPLICATION_KEY="${OVH_APPLICATION_KEY:-$(op read 'op://tuist-k8s-staging/OVH_API/application-key')}"
export OVH_APPLICATION_SECRET="${OVH_APPLICATION_SECRET:-$(op read 'op://tuist-k8s-staging/OVH_API/application-secret')}"
export OVH_CONSUMER_KEY="${OVH_CONSUMER_KEY:-$(op read 'op://tuist-k8s-staging/OVH_API/consumer-key')}"

cd "$(git rev-parse --show-toplevel)/infra/cluster-api-provider-tuist"
go run ./cmd/prep --provider ovh --fleet "$fleet" --pubkey "$pubkey" --server "$service"
