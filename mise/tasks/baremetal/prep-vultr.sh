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

ssh -i "$key" -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
  -o ConnectTimeout=20 "root@$host" 'bash -s' <<'REMOTE'
set -euo pipefail

log() { echo "prep-vultr: $*"; }

if mountpoint -q /data; then
  log "/data already mounted from $(findmnt -no SOURCE /data) ($(findmnt -no FSTYPE /data)); nothing to do"
  exit 0
fi

root_dev="$(findmnt -no SOURCE /)"
case "$root_dev" in
  /dev/md*) ;;
  *) log "root is $root_dev, not an md array; this box was not installed with RAID 1"; exit 1 ;;
esac

# Keep the leg on the disk that holds the ESP, so the boot-critical disk carries
# root, and hand the other disk to /data.
esp_disk="/dev/$(lsblk -no PKNAME "$(findmnt -no SOURCE /boot/efi)")"

# Every member, with the state mdadm reports for it. A fresh RAID 1 install
# mirrors the entire device before the array is clean, throttled to
# /proc/sys/dev/raid/speed_limit_max (200 MB/s by default), which on a ~900G
# pair runs for over an hour no matter how little is stored. Waiting for it here
# would be waiting for a copy onto the very disk this is about to wipe and
# reformat as XFS: the rebuilding leg is the non-ESP one, which is the leg /data
# takes. Removing it aborts the rebuild and leaves the root on the complete copy.
legs="$(mdadm --detail "$root_dev" | awk '$NF ~ /^\/dev\// && $NF !~ /:$/ {
  dev = $NF; s = ""; for (i = 5; i < NF; i++) s = s (s ? " " : "") $i; print dev "|" s }')"

data_leg=""; data_state=""
while IFS='|' read -r leg state; do
  [ -z "$leg" ] && continue
  [ "/dev/$(lsblk -no PKNAME "$leg")" = "$esp_disk" ] && continue
  data_leg="$leg"; data_state="$state"
done <<< "$legs"
[ -n "$data_leg" ] || { log "no leg off the ESP disk ($esp_disk) to hand to /data"; exit 1; }

# The only unsafe case: this leg is the array's sole in-sync copy while another
# is rebuilding, so taking it would leave the root on an incomplete member.
if [ "${data_state#*active sync}" != "$data_state" ] && grep -qE 'recovery|resync' /proc/mdstat; then
  log "$data_leg is the only in-sync leg while $root_dev rebuilds; taking it would leave the root incomplete"
  grep -E 'recovery|resync' /proc/mdstat >&2
  exit 1
fi

log "root=$root_dev esp_disk=$esp_disk -> handing $data_leg to /data (mdadm state: ${data_state:-unknown})"

mdadm "$root_dev" --fail "$data_leg"
# md does not release a device the moment it is failed: an in-flight rebuild has
# to wind down first, and --remove returns EBUSY until it has.
for _ in $(seq 1 60); do
  mdadm "$root_dev" --remove "$data_leg" 2>/dev/null && break
  sleep 2
done
if mdadm --detail "$root_dev" | grep -q "$data_leg"; then
  log "$data_leg is still a member of $root_dev after 120s; refusing to format it"
  exit 1
fi
# Drop to a clean single-device array so the root does not sit permanently
# "degraded" and trip array monitoring.
mdadm --grow "$root_dev" --raid-devices=1 --force

wipefs -a "$data_leg"
# crc + project quotas: the quota program refuses anything that is not xfs with
# prjquota, and the ceiling it assigns comes straight from the PVC.
mkfs.xfs -f -m crc=1 "$data_leg"

mkdir -p /data
uuid="$(blkid -s UUID -o value "$data_leg")"
sed -i '\| /data |d' /etc/fstab
# nofail so a failed data disk cannot block boot -- placing /data off the ESP
# disk is only worth something if the box still comes up without it. The quota
# program then reports the volume as unbounded and kura_volume_quota_enforced
# goes to 0, which is the intended loud no-op rather than an unschedulable node.
# Pass 0 for the same reason: fsck must not hold boot on this filesystem.
echo "UUID=$uuid /data xfs defaults,prjquota,nofail,x-systemd.device-timeout=30s 0 0" >> /etc/fstab
systemctl daemon-reload
mount /data

# The array changed shape, so persist it or the next boot assembles the old one.
mdadm --detail --scan > /etc/mdadm/mdadm.conf
update-initramfs -u >/dev/null 2>&1

log "done"
REMOTE

echo
echo "verifying the self-join gates on $host:"
ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=20 "root@$host" 'bash -s' <<'CHECK'
set -eu
data=/data
p() { printf "  %-34s %s\n" "$1" "$2"; }
mountpoint -q "$data" && p "/data is a mountpoint" PASS || { p "/data is a mountpoint" FAIL; exit 1; }
[ "$(findmnt -no SOURCE $data)" != "$(findmnt -no SOURCE /)" ] && p "/data is not the root filesystem" PASS || { p "/data is not the root filesystem" FAIL; exit 1; }
[ "$(findmnt -no FSTYPE $data)" = xfs ] && p "/data is xfs" PASS || { p "/data is xfs" FAIL; exit 1; }
case ",$(findmnt -no OPTIONS $data)," in
  *,prjquota,*|*,pquota,*) p "/data has project quotas" PASS ;;
  *) p "/data has project quotas" FAIL; exit 1 ;;
esac
p "usable /data" "$(df -h $data | awk 'NR==2{print $2}')"
CHECK
