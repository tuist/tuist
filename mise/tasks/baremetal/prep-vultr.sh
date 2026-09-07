#!/usr/bin/env bash
#MISE description="Prep a Vultr bare-metal box: split the installer's mirror into a single-disk root plus the separate XFS /data the cache volume quota needs"
#
# Why this is a conversion rather than an install, unlike prep-ovh / prep-dedibox:
# Vultr's API exposes no partitioning control, and its installer offers only
# "RAID 1 across both disks" (one filesystem spanning the pair) or "no RAID".
# Neither produces the mirrored root plus separate XFS /data those installs lay
# down. So the box is ordered as RAID 1 and converted here: the mirror is split,
# the freed disk becomes /data, and the root keeps running on the remaining leg.
# No reinstall, no reboot, no bootloader change.
#
# What that costs: the root loses its mirror. On a two-disk box Vultr's installer
# forces a choice between mirroring everything and having a second filesystem,
# and /data is the one the cluster actually gates on -- tuist.kuraVolumeQuotaProgram
# leaves every cache volume unbounded without an XFS /data carrying project
# quotas, and the self-join refuses a box that cannot enforce.
#
# /data is placed on the disk that does NOT hold the ESP, so losing the data disk
# leaves a box that still boots.
#
# Usage:
#   mise run baremetal:prep-vultr <host>
#   e.g. mise run baremetal:prep-vultr 64.176.17.88
#
# The fleet key comes from the env's 1Password vault (tuist-k8s-<env>, derived
# from PREP_NAMESPACE; override with PREP_VAULT). Re-running on a prepared box is
# a no-op.

set -euo pipefail

host="${1:-}"
ns="${PREP_NAMESPACE:-tuist-production}"
env="${ns#tuist-}"
vault="${PREP_VAULT:-tuist-k8s-$env}"
item="${PREP_SSH_ITEM:-VULTR_FLEET_SSH}"

if [ -z "$host" ]; then
  echo "usage: mise run baremetal:prep-vultr <host>" >&2
  exit 2
fi

key="$(mktemp)"
trap 'rm -f "$key"' EXIT
chmod 600 "$key"
op read "op://$vault/$item/private-key" > "$key" 2>/dev/null ||
  { echo "no fleet key at op://$vault/$item/private-key" >&2; exit 1; }

root="$(git rev-parse --show-toplevel)"
script="$root/infra/cluster-api-provider-tuist/controllers/linux/vultr_convert.sh"
[ -f "$script" ] || { echo "missing conversion script: $script" >&2; exit 1; }

# The reconciler embeds this same file and runs it as its Converting stage, so
# out-of-band prep and the controller cannot drift apart.
ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=20 "root@$host" 'bash -s' < "$script"
