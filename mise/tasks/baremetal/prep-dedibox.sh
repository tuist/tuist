#!/usr/bin/env bash
#MISE description="Prep a pre-ordered Dedibox (install Ubuntu + the fleet key) so the fleet self-joins it"
#
# Adoption is now a fast self-join, so a box must be prepared before it is tagged
# into the pool. This installs Ubuntu with the fleet's SSH key + the tuist login so
# the controller can self-join it on the next claim — no hand-installing.
#
# Usage:
#   mise run baremetal:prep-dedibox <server-id> [fleet-name]
#   e.g. mise run baremetal:prep-dedibox 188785
#
# Reads the fleet pubkey from the operator-minted <fleet>-ssh Secret (so the fleet
# must be deployed first) and the Dedibox IAM key from 1Password. Override the
# cluster via PREP_KUBE_CONTEXT / PREP_NAMESPACE, or the creds via env.

set -euo pipefail

server_id="${1:-}"
fleet="${2:-tuist-tuist-dedibox-fleet}"
ns="${PREP_NAMESPACE:-tuist-staging}"

if [ -z "$server_id" ]; then
  echo "usage: mise run baremetal:prep-dedibox <server-id> [fleet-name]" >&2
  echo "  e.g. mise run baremetal:prep-dedibox 188785" >&2
  exit 2
fi

kube=(kubectl)
[ -n "${PREP_KUBE_CONTEXT:-}" ] && kube=(kubectl --context "$PREP_KUBE_CONTEXT")

pubkey="$("${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.id_ed25519\.pub}' 2>/dev/null | base64 -d || true)"
[ -z "$pubkey" ] && { echo "no id_ed25519.pub in secret ${fleet}-ssh (-n $ns); is the fleet deployed and the key minted?" >&2; exit 1; }

# The private key is needed to SSH in after install and set NOPASSWD sudo.
keydir="$(mktemp -d)"; trap 'rm -rf "$keydir"' EXIT
"${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.id_ed25519}' | base64 -d > "$keydir/id_ed25519"
chmod 600 "$keydir/id_ed25519"

export DEDIBOX_SCW_SECRET_KEY="${DEDIBOX_SCW_SECRET_KEY:-$(op read 'op://tuist-k8s-staging/DEDIBOX_SCW_API/secret-key')}"
export DEDIBOX_SCW_PROJECT_ID="${DEDIBOX_SCW_PROJECT_ID:-$(op read 'op://tuist-k8s-staging/DEDIBOX_SCW_API/project-id')}"

cd "$(git rev-parse --show-toplevel)/infra/cluster-api-provider-tuist"
go run ./cmd/prep --provider dedibox --fleet "$fleet" --pubkey "$pubkey" --privkey "$keydir/id_ed25519" --server "$server_id"
