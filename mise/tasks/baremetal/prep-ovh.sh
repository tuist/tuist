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

root="$(git rev-parse --show-toplevel)"
cd "$root/infra/cluster-api-provider-tuist"
go run ./cmd/prep --provider ovh --fleet "$fleet" --pubkey "$pubkey" --server "$service"

if [ -n "${PREP_SKIP_MARK:-}" ]; then
  echo "PREP_SKIP_MARK set — ${service} is prepped but left unnamed; release it with 'mise run baremetal:mark-ovh ${service} <display-name>'" >&2
  exit 0
fi

# Set the box's displayName into the pool as the final step — the adoption trigger.
# The box is prepped now, so the controller self-joins it the moment the prefix
# matches. The prefix is read from the deployed fleet template (one source of
# truth), then applied via the same path as baremetal:mark-ovh. mark-ovh signs
# against OVH_API_BASE, so map the entity OVH_ENDPOINT selects to its API base.
prefix="$("${kube[@]}" -n "$ns" get ovhdedicatedmachinetemplate "$fleet" -o jsonpath='{.spec.template.spec.adoptDisplayNamePrefix}' 2>/dev/null || true)"
[ -z "$prefix" ] && { echo "prepped ${service} but could not read adoptDisplayNamePrefix from ovhdedicatedmachinetemplate/${fleet} (-n $ns); name it manually: mise run baremetal:mark-ovh ${service} <display-name>" >&2; exit 1; }
case "$OVH_ENDPOINT" in
  ovh-ca) ovh_base="https://ca.api.ovh.com/1.0" ;;
  ovh-eu) ovh_base="https://eu.api.ovh.com/1.0" ;;
  *)      ovh_base="https://api.us.ovhcloud.com/1.0" ;;
esac
OVH_API_BASE="${OVH_API_BASE:-$ovh_base}" bash "$root/mise/tasks/baremetal/mark-ovh.sh" "$service" "$prefix"
