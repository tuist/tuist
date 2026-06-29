#!/usr/bin/env bash
#MISE description="Prep a pre-ordered Dedibox (install Ubuntu + the fleet key) and tag it into the pool"
#
# Adoption is a fast self-join, so a box must be prepared before it is tagged into
# the pool. This installs Ubuntu with the fleet's SSH key + the tuist login, then —
# as the final step — stamps the fleet's adoptTag so the controller self-joins it on
# the next claim (no hand-installing, no separate mark step). Tagging last, here,
# also removes the tag-before-prep footgun. Set PREP_SKIP_MARK=1 to prep without
# tagging (to stage capacity ahead and release later with baremetal:mark-dedibox).
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

# The install sets this as the login password; the self-join uses it to establish
# NOPASSWD sudo. Run mint-fleet-key first if it's missing.
sudopw="$("${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.sudo-password}' 2>/dev/null | base64 -d || true)"
[ -z "$sudopw" ] && { echo "no sudo-password in secret ${fleet}-ssh (-n $ns); run 'mise run baremetal:mint-fleet-key ${fleet}' first" >&2; exit 1; }

export DEDIBOX_SCW_SECRET_KEY="${DEDIBOX_SCW_SECRET_KEY:-$(op read 'op://tuist-k8s-staging/DEDIBOX_SCW_API/secret-key')}"
export DEDIBOX_SCW_PROJECT_ID="${DEDIBOX_SCW_PROJECT_ID:-$(op read 'op://tuist-k8s-staging/DEDIBOX_SCW_API/project-id')}"

root="$(git rev-parse --show-toplevel)"
cd "$root/infra/cluster-api-provider-tuist"
go run ./cmd/prep --provider dedibox --fleet "$fleet" --pubkey "$pubkey" --sudo-password "$sudopw" --server "$server_id"

if [ -n "${PREP_SKIP_MARK:-}" ]; then
  echo "PREP_SKIP_MARK set — ${server_id} is prepped but left untagged; release it with 'mise run baremetal:mark-dedibox ${server_id} <tag>'" >&2
  exit 0
fi

# Tag the box into the pool as the final step — this is the adoption trigger, and
# the box is prepped now, so the controller self-joins it the moment it sees the
# tag. The tag is read from the deployed fleet template (one source of truth), then
# applied via the same path as baremetal:mark-dedibox.
tag="$("${kube[@]}" -n "$ns" get dediboxmachinetemplate "$fleet" -o jsonpath='{.spec.template.spec.adoptTag}' 2>/dev/null || true)"
[ -z "$tag" ] && { echo "prepped ${server_id} but could not read adoptTag from dediboxmachinetemplate/${fleet} (-n $ns); tag it manually: mise run baremetal:mark-dedibox ${server_id} <tag>" >&2; exit 1; }
bash "$root/mise/tasks/baremetal/mark-dedibox.sh" "$server_id" "$tag"
