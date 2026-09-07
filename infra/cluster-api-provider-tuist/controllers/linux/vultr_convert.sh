# Canonical Vultr disk conversion, shared by two callers so they cannot drift:
# the VultrMachine reconciler embeds this file and runs it over SSH as its
# Converting stage, and `mise run baremetal:prep-vultr` ships the same bytes for
# out-of-band prep. Runs as root with `bash -s`, is idempotent, and exits
# non-zero if the layout it produced would not satisfy the self-join.
set -euo pipefail

log() { echo "prep-vultr: $*"; }

# An existing /data is not proof of a good /data: one that is ext4, or mounted
# without project quotas, would leave every cache volume unbounded. So skip the
# conversion but always fall through to the gates below, which decide.
if mountpoint -q /data; then
  log "/data already mounted from $(findmnt -no SOURCE /data) ($(findmnt -no FSTYPE /data)); skipping the conversion"
else

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

fi
# Verify rather than assume. These are exactly the conditions
# tuist.kuraVolumeQuotaProgram checks, so a box that passes here is one the
# self-join will accept, and a non-zero exit is the signal the caller acts on.
gate() { printf 'prep-vultr: gate %-28s %s\n' "$1" "$2"; }
fail=0
mountpoint -q /data || { gate "/data is a mountpoint" FAIL; fail=1; }
[ "$(findmnt -no SOURCE /data 2>/dev/null)" != "$(findmnt -no SOURCE /)" ] || { gate "/data is not the root fs" FAIL; fail=1; }
[ "$(findmnt -no FSTYPE /data 2>/dev/null)" = xfs ] || { gate "/data is xfs" FAIL; fail=1; }
case ",$(findmnt -no OPTIONS /data 2>/dev/null)," in
  *,prjquota,*|*,pquota,*) ;;
  *) gate "/data has project quotas" FAIL; fail=1 ;;
esac
[ "$fail" -eq 0 ] || { log "converted layout does not satisfy the self-join gates"; exit 1; }

# Machine-readable tail the reconciler parses into status.converted.
echo "prep-vultr: RESULT device=$(findmnt -no SOURCE /data) fstype=$(findmnt -no FSTYPE /data) quota=true size=$(df -h /data | awk 'NR==2{print $2}')"
log "all four gates pass"

