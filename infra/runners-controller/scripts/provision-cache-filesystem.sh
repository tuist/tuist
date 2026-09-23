#!/usr/bin/env bash
# Run explicitly on a Linux runner host before enabling cache volumes.
set -euo pipefail
root=${1:-/var/lib/tuist-runner-cache}
size_gb=${2:-200}
[[ $EUID == 0 ]] || { echo 'Run as root on the runner host.' >&2; exit 1; }
[[ "$root" =~ ^/[a-zA-Z0-9/_-]+$ && "$root" != / && "$size_gb" =~ ^[0-9]+$ && "$size_gb" -ge 64 ]] || exit 2
for tool in fallocate mkfs.xfs findmnt systemd-escape systemctl; do command -v "$tool" >/dev/null; done
image="${root}.img"
unit=$(systemd-escape --path --suffix=mount "$root")
[[ ! -L "$image" ]] || { echo "Refusing a symlink backing file." >&2; exit 1; }
if ! [[ -f "$image" ]]; then
  [[ ! -e "$image" && ! -L "$image" && ! -e "$image.new" ]] || { echo 'Existing storage requires inspection.' >&2; exit 1; }
  mkdir -p "$root"
  [[ -z $(find "$root" -mindepth 1 -maxdepth 1 -print -quit) ]] || { echo 'Cache directory must be empty.' >&2; exit 1; }
  # Fully reserve the backing bytes up front. A growing sparse outer file could
  # fill kubelet's root even though the inner filesystem has its own watermarks.
  available=$(df -B1 --output=avail "$(dirname "$root")" | tail -1 | tr -d ' ')
  required=$(( (size_gb + 40) * 1000000000 ))
  (( available >= required )) || { echo 'Insufficient space to reserve the cache plus 40 GB for the host.' >&2; exit 1; }
  trap 'rm -f "$image.new"' EXIT
  fallocate -l "$((size_gb * 1000000000))" "$image.new"
  mkfs.xfs -K -q -m reflink=1 "$image.new"
  chmod 600 "$image.new"
  sync "$image.new"
  mv "$image.new" "$image"
  trap - EXIT
fi
# No existing file is reformatted, resized, or replaced on a retry.
cat > "/etc/systemd/system/$unit" <<UNIT
[Unit]
Description=Tuist runner cache filesystem
Before=kubelet.service

[Mount]
What=$image
Where=$root
Type=xfs
Options=loop,nodev,nosuid,nodiscard,X-fstrim.notrim

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now "$unit"
findmnt --mountpoint "$root" --types xfs >/dev/null
printf 'Cache filesystem ready at %s\n' "$root"
