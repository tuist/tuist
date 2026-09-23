#!/bin/sh
# The rack's boot server, run by the rack-boot DaemonSet on the rack's edge
# node with host networking. On the provisioning address it serves, over TFTP,
# the installer ISO's shim, Ubuntu's signed network GRUB, the installer's kernel
# and initrd, and a GRUB menu per host; over HTTP, the installer ISO and each
# host's autoinstall seed. The per-host files are what the operator publishes
# to the fleet's boot Secret, mounted at $SEEDS: <mac>.grub.cfg,
# <mac>.user-data and <mac>.meta-data, with the MAC hyphenated. A host with
# nothing published gets nothing and falls through to its next boot entry.
#
# Environment: BOOT_ADDRESS, HTTP_PORT, ISO_URL, ISO_SHA256, STATE (a host
# directory kept across restarts), SEEDS, NETBOOT (the network GRUB).
# RACK_BOOT_SOURCE_ONLY=1 defines the functions without serving, for the tests.
set -eu

STATE="${STATE:-/var/lib/tuist-rack-boot}"
SEEDS="${SEEDS:-/etc/rack-boot/seeds}"
NETBOOT="${NETBOOT:-/usr/share/rack-netboot}"
tftp="$STATE/tftp"
http="$STATE/http"

log() { echo "rack-boot: $*"; }

# Downloads and verifies the installer ISO once per checksum, and lays out
# what every netboot shares.
prepare() {
  mkdir -p "$tftp/grub/hosts" "$tftp/ubuntu" "$http/ubuntu" "$http/hosts"
  iso="$http/ubuntu/ubuntu.iso"
  if [ "$(cat "$STATE/iso.sha256" 2>/dev/null)" != "$ISO_SHA256" ]; then
    rm -f "$iso" "$STATE/iso.sha256"
    log "downloading $ISO_URL"
    curl -fsSL --retry 5 --retry-all-errors -o "$iso.part" "$ISO_URL"
    if ! echo "$ISO_SHA256  $iso.part" | sha256sum -c -s; then
      log "$ISO_URL does not match sha256 $ISO_SHA256" >&2
      rm -f "$iso.part"
      return 1
    fi
    mv "$iso.part" "$iso"
    echo "$ISO_SHA256" > "$STATE/iso.sha256"
  fi
  # The kernel and initrd come from the ISO the installer then loads, so the
  # modules in its squashfs match the running kernel, and so does the shim,
  # the one the ISO boots with from a stick.
  bsdtar -xOf "$iso" casper/vmlinuz > "$tftp/ubuntu/vmlinuz"
  bsdtar -xOf "$iso" casper/initrd > "$tftp/ubuntu/initrd"
  bsdtar -xOf "$iso" EFI/boot/bootx64.efi > "$tftp/bootx64.efi"
  cp "$NETBOOT/grubx64.efi" "$tftp/"
  # GRUB reads grub.cfg-01-<mac> before grub.cfg when there is one, and
  # grub.cfg looks for the host's menu by the MAC GRUB booted from; a host with
  # neither returns to its firmware's next boot entry.
  cat > "$tftp/grub/grub.cfg" <<'GRUB'
set timeout=0
configfile $prefix/hosts/${net_default_mac}.cfg
exit 1
GRUB
}

# Mirrors the Secret into the served trees. Files are copied rather than
# linked, so neither server follows a link out of its root.
sync_seeds() {
  wanted=" "
  for cfg in "$SEEDS"/*.grub.cfg; do
    [ -f "$cfg" ] || continue
    mac="$(basename "$cfg" .grub.cfg)"
    case "$mac" in
      [0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]) ;;
      *) continue ;;
    esac
    [ -f "$SEEDS/$mac.user-data" ] && [ -f "$SEEDS/$mac.meta-data" ] || continue
    wanted="$wanted$mac "
    mkdir -p "$http/hosts/$mac" "$tftp/grub/hosts"
    : > "$http/hosts/$mac/vendor-data"
    for f in user-data meta-data; do
      cmp -s "$SEEDS/$mac.$f" "$http/hosts/$mac/$f" || { cp "$SEEDS/$mac.$f" "$http/hosts/$mac/$f.new" && mv "$http/hosts/$mac/$f.new" "$http/hosts/$mac/$f"; }
    done
    changed=
    for target in "$tftp/grub/grub.cfg-01-$mac" "$tftp/grub/hosts/$(echo "$mac" | tr - :).cfg"; do
      cmp -s "$cfg" "$target" || { cp "$cfg" "$target.new" && mv "$target.new" "$target" && changed=1; }
    done
    [ -z "$changed" ] || log "serving the install for $mac"
  done
  for dir in "$http/hosts"/*; do
    [ -d "$dir" ] || continue
    mac="$(basename "$dir")"
    case "$wanted" in *" $mac "*) continue ;; esac
    rm -rf "$dir" "$tftp/grub/grub.cfg-01-$mac" "$tftp/grub/hosts/$(echo "$mac" | tr - :).cfg"
    log "withdrew the install for $mac"
  done
}

serve() {
  : "${BOOT_ADDRESS:?}" "${HTTP_PORT:?}" "${ISO_URL:?}" "${ISO_SHA256:?}"
  prepare
  until ip -o -4 addr show | grep -q " inet $BOOT_ADDRESS/"; do
    log "waiting for $BOOT_ADDRESS, which the rack-edge pod puts on the switch port"
    sleep 5
  done
  sync_seeds
  dnsmasq --no-daemon --port=0 --bind-dynamic --listen-address="$BOOT_ADDRESS" \
    --enable-tftp --tftp-root="$tftp" --log-facility=- &
  tftp_pid=$!
  busybox-extras httpd -f -vv -p "$BOOT_ADDRESS:$HTTP_PORT" -h "$http" &
  http_pid=$!
  trap 'kill "$tftp_pid" "$http_pid" 2>/dev/null' EXIT INT TERM
  while kill -0 "$tftp_pid" 2>/dev/null && kill -0 "$http_pid" 2>/dev/null; do
    sync_seeds
    sleep 5
  done
  log "a server exited" >&2
  return 1
}

[ "${RACK_BOOT_SOURCE_ONLY:-}" = 1 ] || serve
