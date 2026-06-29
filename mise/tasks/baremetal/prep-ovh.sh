#!/usr/bin/env bash
#MISE description="Prep a pre-ordered OVH box (install Ubuntu + the fleet key) and name it into the pool"
#
# Adoption is a fast self-join, so a box must be prepared before its adoption
# displayName is set. This installs Ubuntu with the fleet's SSH key, then — as the
# final step — sets the box's displayName to the fleet's adoptDisplayNamePrefix so
# the controller self-joins it on the next claim (no hand-installing, no separate
# mark step). Naming last, here, also removes the name-before-prep footgun. Set
# PREP_SKIP_MARK=1 to prep without naming (to stage capacity ahead and release
# later with baremetal:mark-ovh).
#
# Usage:
#   mise run baremetal:prep-ovh <service-name> [fleet-name]
#   e.g. mise run baremetal:prep-ovh ns543284.ip-144-217-252.net
#
# The fleet pubkey and the OVH API triple come from the env's 1Password vault
# (tuist-k8s-<env>, derived from PREP_NAMESPACE; override with PREP_VAULT) — so a
# box can be prepped with no cluster access. Falls back to the in-cluster
# <fleet>-ssh Secret for fleets still on controller-minted keys. OVH_ENDPOINT
# selects the entity (default ovh-us).

set -euo pipefail

service="${1:-}"
fleet="${2:-tuist-tuist-ovh-fleet}"
ns="${PREP_NAMESPACE:-tuist-staging}"

if [ -z "$service" ]; then
  echo "usage: mise run baremetal:prep-ovh <service-name> [fleet-name]" >&2
  echo "  e.g. mise run baremetal:prep-ovh ns543284.ip-144-217-252.net" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel)"
env="${ns#tuist-}"
vault="${PREP_VAULT:-tuist-k8s-$env}"
values="$root/infra/helm/tuist/values-managed-${env}.yaml"

kube=(kubectl)
[ -n "${PREP_KUBE_CONTEXT:-}" ] && kube=(kubectl --context "$PREP_KUBE_CONTEXT")

# Resolve the fleet's values path. A map fleet (…-ovh-fleet-<key>, e.g.
# tuist-tuist-ovh-fleet-us-east) reads .ovhFleets.<key>; the singular ca-east
# fleet (tuist-tuist-ovh-fleet) reads .ovhFleet. `##*-ovh-fleet-` strips the
# componentName prefix to the bare key, and returns the name unchanged (no map
# lookup) for the singular fleet.
key="${fleet##*-ovh-fleet-}"
cfg=".ovhFleet"
if [ "$key" != "$fleet" ] && [ "$(yq ".ovhFleets.\"$key\"" "$values" 2>/dev/null)" != "null" ]; then
  cfg=".ovhFleets.\"$key\""
fi

# SSH key: prefer the 1Password-owned item (no cluster access needed); fall back
# to the in-cluster <fleet>-ssh Secret for fleets still on controller-minted keys.
item="$(yq "${cfg}.sshExternalSecret.item" "$values" 2>/dev/null || true)"
[ "$item" = "null" ] && item=""
pubkey=""
[ -n "$item" ] && pubkey="$(op read "op://$vault/$item/public-key" 2>/dev/null || true)"
[ -z "$pubkey" ] && pubkey="$("${kube[@]}" -n "$ns" get secret "${fleet}-ssh" -o jsonpath='{.data.id_ed25519\.pub}' 2>/dev/null | base64 -d || true)"
[ -z "$pubkey" ] && { echo "no fleet pubkey: tried op://$vault/${item:-<unset>}/public-key and the ${fleet}-ssh Secret (-n $ns); is the 1Password item present, or the key minted?" >&2; exit 1; }

# go-ovh reads these from the env. OVH_ENDPOINT must match the box's entity (the
# token is bound to it); the BHS box is on an OVHcloud US account.
export OVH_ENDPOINT="${OVH_ENDPOINT:-ovh-us}"
export OVH_APPLICATION_KEY="${OVH_APPLICATION_KEY:-$(op read "op://$vault/OVH_API/application-key")}"
export OVH_APPLICATION_SECRET="${OVH_APPLICATION_SECRET:-$(op read "op://$vault/OVH_API/application-secret")}"
export OVH_CONSUMER_KEY="${OVH_CONSUMER_KEY:-$(op read "op://$vault/OVH_API/consumer-key")}"

cd "$root/infra/cluster-api-provider-tuist"
go run ./cmd/prep --provider ovh --fleet "$fleet" --pubkey "$pubkey" --server "$service"

if [ -n "${PREP_SKIP_MARK:-}" ]; then
  echo "PREP_SKIP_MARK set — ${service} is prepped but left unnamed; release it with 'mise run baremetal:mark-ovh ${service} <display-name>'" >&2
  exit 0
fi

# Set the box's displayName into the pool as the final step — the adoption trigger.
# The box is prepped now, so the controller self-joins it the moment the prefix
# matches. Read the prefix from the env's values file (present before the fleet is
# ever deployed, so this stays a cold-start step); fall back to a deployed
# template. Override via PREP_ADOPT_DISPLAY_NAME. mark-ovh signs against
# OVH_API_BASE, so map the entity OVH_ENDPOINT selects to its API base.
prefix="${PREP_ADOPT_DISPLAY_NAME:-}"
[ -z "$prefix" ] && prefix="$(yq "${cfg}.machine.adoptDisplayNamePrefix" "$values" 2>/dev/null || true)"
[ "$prefix" = "null" ] && prefix=""
[ -z "$prefix" ] && prefix="$("${kube[@]}" -n "$ns" get ovhdedicatedmachinetemplate "$fleet" -o jsonpath='{.spec.template.spec.adoptDisplayNamePrefix}' 2>/dev/null || true)"
[ -z "$prefix" ] && { echo "prepped ${service} but could not resolve the adoptDisplayNamePrefix (looked in ${values} and ovhdedicatedmachinetemplate/${fleet}); name it manually: mise run baremetal:mark-ovh ${service} <display-name>" >&2; exit 1; }
case "$OVH_ENDPOINT" in
  ovh-ca) ovh_base="https://ca.api.ovh.com/1.0" ;;
  ovh-eu) ovh_base="https://eu.api.ovh.com/1.0" ;;
  *)      ovh_base="https://api.us.ovhcloud.com/1.0" ;;
esac
OVH_API_BASE="${OVH_API_BASE:-$ovh_base}" bash "$root/mise/tasks/baremetal/mark-ovh.sh" "$service" "$prefix"
