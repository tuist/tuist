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
# The fleet pubkey + sudo-password and the Dedibox IAM key come from the env's
# 1Password vault (tuist-k8s-<env>, derived from PREP_NAMESPACE; override with
# PREP_VAULT) — so a box can be prepped with no cluster access. Falls back to the
# in-cluster <fleet>-ssh Secret for fleets still on controller-minted keys
# (PREP_KUBE_CONTEXT selects the cluster for that fallback).

set -euo pipefail

server_id="${1:-}"
fleet="${2:-tuist-tuist-dedibox-fleet}"
ns="${PREP_NAMESPACE:-tuist-staging}"

if [ -z "$server_id" ]; then
  echo "usage: mise run baremetal:prep-dedibox <server-id> [fleet-name]" >&2
  echo "  e.g. mise run baremetal:prep-dedibox 188785" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
env="${ns#tuist-}"
vault="${PREP_VAULT:-tuist-k8s-$env}"
values="$root/infra/helm/tuist/values-managed-${env}.yaml"

kube=(kubectl)
[ -n "${PREP_KUBE_CONTEXT:-}" ] && kube=(kubectl --context "$PREP_KUBE_CONTEXT")

# SSH key: prefer the 1Password-owned item (no cluster access needed); fall back
# to the in-cluster <fleet>-ssh Secret for fleets still on controller-minted keys.
item="$(yq '.dediboxFleet.sshExternalSecret.item' "$values" 2>/dev/null || true)"
[ "$item" = "null" ] && item=""
pubkey=""; sudopw=""
if [ -n "$item" ]; then
  pubkey="$(op read "op://$vault/$item/public-key" 2>/dev/null || true)"
  sudopw="$(op read "op://$vault/$item/sudo-password" 2>/dev/null || true)"
fi
if [ -z "$pubkey" ]; then
  pubkey="$("${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.id_ed25519\.pub}' 2>/dev/null | base64 -d || true)"
  sudopw="$("${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.sudo-password}' 2>/dev/null | base64 -d || true)"
fi
[ -z "$pubkey" ] && { echo "no fleet pubkey: tried op://$vault/${item:-<unset>}/public-key and the ${fleet}-ssh Secret (-n $ns); is the 1Password item present, or the key minted?" >&2; exit 1; }
# The install sets this as the login password; the self-join uses it to establish NOPASSWD sudo.
[ -z "$sudopw" ] && { echo "no sudo-password: tried op://$vault/${item:-<unset>}/sudo-password and the ${fleet}-ssh Secret (-n $ns)" >&2; exit 1; }

export DEDIBOX_SCW_SECRET_KEY="${DEDIBOX_SCW_SECRET_KEY:-$(op read "op://$vault/DEDIBOX_SCW_API/secret-key")}"
export DEDIBOX_SCW_PROJECT_ID="${DEDIBOX_SCW_PROJECT_ID:-$(op read "op://$vault/DEDIBOX_SCW_API/project-id")}"

cd "$root/infra/cluster-api-provider-tuist"
go run ./cmd/prep --provider dedibox --fleet "$fleet" --pubkey "$pubkey" --sudo-password "$sudopw" --server "$server_id"

if [ -n "${PREP_SKIP_MARK:-}" ]; then
  echo "PREP_SKIP_MARK set — ${server_id} is prepped but left untagged; release it with 'mise run baremetal:mark-dedibox ${server_id} <tag>'" >&2
  exit 0
fi

# Tag the box into the pool as the final step — this is the adoption trigger, and
# the box is prepped now, so the controller self-joins it the moment it sees the
# tag. Read the tag from the env's values file (present before the fleet is ever
# deployed, so this stays a cold-start step); fall back to a deployed
# DediboxMachineTemplate. Override via PREP_ADOPT_TAG.
tag="${PREP_ADOPT_TAG:-}"
[ -z "$tag" ] && tag="$(yq '.dediboxFleet.machine.adoptTag' "$values" 2>/dev/null || true)"
[ "$tag" = "null" ] && tag=""
[ -z "$tag" ] && tag="$("${kube[@]}" -n "$ns" get dediboxmachinetemplate "$fleet" -o jsonpath='{.spec.template.spec.adoptTag}' 2>/dev/null || true)"
[ -z "$tag" ] && { echo "prepped ${server_id} but could not resolve the adoptTag (looked in ${values} and dediboxmachinetemplate/${fleet}); tag it manually: mise run baremetal:mark-dedibox ${server_id} <tag>" >&2; exit 1; }
bash "$root/mise/tasks/baremetal/mark-dedibox.sh" "$server_id" "$tag"
