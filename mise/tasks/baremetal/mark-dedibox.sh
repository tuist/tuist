#!/usr/bin/env bash
#MISE description="Tag a pre-ordered Dedibox so a CAPI fleet can adopt it (replaces the box's tags)"
#
# The DediboxMachine reconciler adopts a box by its per-fleet tag (the env
# boundary, since every Dedibox shares the org's default Scaleway project). The
# operator only has to order the box and stamp that tag; this scripts the stamp.
#
# Usage:
#   DEDIBOX_SCW_SECRET_KEY=... mise run baremetal:mark-dedibox <server-id> <tag> [zone]
#
# e.g. mise run baremetal:mark-dedibox 188785 tuist-kura-staging
#
# The secret key is the default-project Dedibox IAM key (needs DediboxFullAccess);
# pull it from 1Password:
#   export DEDIBOX_SCW_SECRET_KEY="$(op read 'op://tuist-k8s-staging/DEDIBOX_SCW_API/secret-key')"
#
# Zone is auto-detected across the Dedibox zones (fr-par-1, fr-par-2, nl-ams-1)
# when omitted. NOTE: this sets the box's tag list to exactly [<tag>], replacing
# any existing tags — fine for a dedicated fleet box.

set -euo pipefail

server_id="${1:-}"
tag="${2:-}"
zone="${3:-}"

if [ -z "$server_id" ] || [ -z "$tag" ]; then
  echo "usage: mise run baremetal:mark-dedibox <server-id> <tag> [zone]" >&2
  echo "  e.g. mise run baremetal:mark-dedibox 188785 tuist-kura-staging" >&2
  exit 2
fi
: "${DEDIBOX_SCW_SECRET_KEY:?export it, e.g. DEDIBOX_SCW_SECRET_KEY=\$(op read 'op://tuist-k8s-staging/DEDIBOX_SCW_API/secret-key')}"

base="https://api.scaleway.com/dedibox/v1"
auth=(-H "X-Auth-Token: ${DEDIBOX_SCW_SECRET_KEY}")

if [ -z "$zone" ]; then
  for z in fr-par-1 fr-par-2 nl-ams-1; do
    if curl -fsS "${auth[@]}" "${base}/zones/${z}/servers/${server_id}" >/dev/null 2>&1; then
      zone="$z"
      break
    fi
  done
  [ -z "$zone" ] && { echo "Dedibox server ${server_id} not found in any zone" >&2; exit 1; }
fi

curl -fsS -X POST "${auth[@]}" -H "Content-Type: application/json" \
  -d "{\"tags\":[\"${tag}\"]}" \
  "${base}/zones/${zone}/servers/${server_id}/tags" >/dev/null

echo "✓ Dedibox ${server_id} (${zone}) tags set to [${tag}]"
