# Shared first-boot conversion. The optional device is a detached Vultr RAID
# leg; otherwise /data must be a fresh, separate XFS filesystem on md.
kura_lvm_setup() (
  set -euo pipefail
  local device="${1:-}" marker=/var/lib/tuist/kura-lvm-device
  local vg=kura-volumes lv=/dev/kura-volumes/data
  local inspection_mount=false
  fail() { echo "kura-lvm: $*" >&2; exit 1; }
  trap 'if [ "$inspection_mount" = true ]; then umount /data; fi' EXIT

  # A failed join can already have started workloads before writing joined-node.
  # Never use that marker alone as permission to destroy a filesystem.
  if [ -e /var/lib/tuist/joined-node ] || systemctl is-active --quiet kubelet; then
    vgs "$vg" >/dev/null 2>&1 || fail "existing node needs a reinstall"
  fi
  if ! command -v pvcreate >/dev/null || ! command -v mkfs.xfs >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y lvm2 xfsprogs
  fi
  mkdir -p /var/lib/tuist
  if ! vgs "$vg" >/dev/null 2>&1; then
    if [ -f "$marker" ]; then
      device="$(cat "$marker")"
    else
      if [ -z "$device" ]; then
        if ! mountpoint -q /data; then
          # Scaleway creates the requested XFS md filesystem but can omit its
          # mount and fstab entry. Inspect only a single unmounted candidate;
          # never infer a data disk from its size or format a raw device here.
          local candidates=() candidate
          while read -r candidate; do
            [ -n "$candidate" ] || continue
            [ -z "$(lsblk -nro MOUNTPOINTS "$candidate" | tr -d '[:space:]')" ] || continue
            candidates+=("$candidate")
          done < <(lsblk -rpno NAME,FSTYPE | awk '$1 ~ /^\/dev\/md/ && $2 == "xfs" { print $1 }' | sort -u)
          [ "${#candidates[@]}" = 1 ] || fail "expected exactly one unmounted XFS md data filesystem"
          mkdir -p /data
          [ -z "$(find /data -mindepth 1 -maxdepth 1 -print -quit)" ] || fail "unmounted /data is not empty"
          # Allow XFS journal replay: norecovery could hide committed files
          # and make a populated filesystem appear empty during inspection.
          mount -t xfs -o ro "${candidates[0]}" /data
          inspection_mount=true
        fi
        [ "$(findmnt -no FSTYPE /data)" = xfs ] || fail "/data is not XFS"
        device="$(readlink -f "$(findmnt -no SOURCE /data)")"
        case "$device" in /dev/md*) ;; *) fail "/data is not on md" ;; esac
        [ "$device" != "$(readlink -f "$(findmnt -no SOURCE /)")" ] || fail "/data is root"
        [ -z "$(find /data -mindepth 1 -maxdepth 1 -print -quit)" ] || fail "/data is not empty"
      fi
      [ -b "$device" ] || fail "not a block device: $device"
      # Persist intent before unmount/wipe, so an interrupted run resumes the
      # same device instead of selecting another disk or formatting an LV.
      printf '%s\n' "$device" > "$marker.new"
      sync "$marker.new"
      mv "$marker.new" "$marker"
      sync /var/lib/tuist
    fi
    if mountpoint -q /data; then
      [ "$(readlink -f "$(findmnt -no SOURCE /data)")" = "$device" ] || fail "unexpected /data source"
      umount /data
      inspection_mount=false
    fi
    [ -z "$(lsblk -nro MOUNTPOINTS "$device" | tr -d '[:space:]')" ] || fail "device still mounted"
    if ! pvs "$device" >/dev/null 2>&1; then
      wipefs -a "$device"
      pvcreate -y "$device"
    fi
    [ -z "$(pvs --noheadings -o vg_name "$device" | tr -d '[:space:]')" ] || fail "device belongs to another VG"
    vgcreate "$vg" "$device"
  fi
  if ! lvs "$vg/data" >/dev/null 2>&1; then
    touch /var/lib/tuist/kura-data-unformatted
    sync /var/lib/tuist
    lvcreate -L 128G -n data "$vg"
  fi
  vgchange -ay "$vg"
  if [ "$(blkid -s TYPE -o value "$lv" || true)" != xfs ]; then
    [ -f /var/lib/tuist/kura-data-unformatted ] || fail "refusing to format existing data LV"
    mkfs.xfs -f "$lv"
  fi
  rm -f /var/lib/tuist/kura-data-unformatted
  mkdir -p /data
  if mountpoint -q /data; then
    [ "$(readlink -f "$(findmnt -no SOURCE /data)")" = "$(readlink -f "$lv")" ] || fail "foreign /data mount"
  else
    local uuid
    uuid="$(blkid -s UUID -o value "$lv")"
    [ -n "$uuid" ] || fail "missing data LV UUID"
    awk '$2 != "/data"' /etc/fstab > /etc/fstab.kura-new
    printf 'UUID=%s /data xfs defaults,prjquota,nofail,x-systemd.device-timeout=30s 0 0\n' "$uuid" >> /etc/fstab.kura-new
    mv /etc/fstab.kura-new /etc/fstab
    systemctl daemon-reload
    mount /data
  fi
)
