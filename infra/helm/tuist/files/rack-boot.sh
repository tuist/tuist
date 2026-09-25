#!/bin/sh
# The rack's boot server, run by the rack-boot DaemonSet on the rack's edge
# node with host networking. On the provisioning address it serves iPXE and
# boot.ipxe over TFTP, and over HTTP the installer's kernel, initrd and ISO and
# each host's iPXE script and autoinstall seed. The per-host files are what the
# operator publishes to the fleet's boot Secret, mounted at $SEEDS:
# <mac>.ipxe, <mac>.user-data and <mac>.meta-data, with the MAC hyphenated. A
# host with nothing published gets nothing and falls through to its next boot
# entry.
#
# Environment: BOOT_ADDRESS, HTTP_PORT, ISO_URL, ISO_SHA256, STATE (a host
# directory kept across restarts), SEEDS, NETBOOT (iPXE).
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
  rm -rf "$tftp"
  mkdir -p "$tftp" "$http/ubuntu" "$http/hosts"
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
  # modules in its squashfs match the running kernel.
  bsdtar -xOf "$iso" casper/vmlinuz > "$http/ubuntu/vmlinuz"
  bsdtar -xOf "$iso" casper/initrd > "$http/ubuntu/initrd"
  cp "$NETBOOT/snponly.efi" "$tftp/"
  lay_out_announce
  # iPXE asks for the host's script by the MAC it booted from; a host with none
  # returns to its firmware's next boot entry.
  cat > "$tftp/boot.ipxe" <<IPXE
#!ipxe
chain http://$BOOT_ADDRESS:$HTTP_PORT/hosts/\${mac:hexhyp}.ipxe || exit 1
IPXE
}

# Lays out cgi-bin/announce, where a machine whose install stick finds nothing
# published for it posts its SMBIOS identity and NICs. Each announcement is
# kept under its UUID in $STATE/announced for a day, and the operator reads
# them over SSH to list the machine as a candidate host. Only the exact lines
# the stick sends are accepted, at most 4096 bytes, for at most 256 machines.
lay_out_announce() {
  mkdir -p "$http/cgi-bin" "$STATE/announced"
  cat >"$http/cgi-bin/announce" <<CGI
#!/bin/sh
dir='$STATE/announced'
CGI
  cat >>"$http/cgi-bin/announce" <<'CGI'
reply() { printf 'Status: %s\r\nContent-Type: text/plain\r\n\r\n%s\n' "$1" "$2"; exit 0; }
[ "$REQUEST_METHOD" = POST ] || reply "405 Method Not Allowed" "post an announcement"
case "${CONTENT_LENGTH:-}" in ''|*[!0-9]*) reply "400 Bad Request" "no content length" ;; esac
[ "$CONTENT_LENGTH" -le 4096 ] || reply "413 Payload Too Large" "at most 4096 bytes"
body=$(head -c "$CONTENT_LENGTH" | grep -v '^$')
if printf '%s\n' "$body" | grep -Evxq 'uuid=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|serial=[A-Za-z0-9._-]{1,64}|product=[ -~]{1,64}|nic=([0-9a-f]{2}:){5}[0-9a-f]{2} [a-z0-9_]{1,16} 0x[0-9a-f]{4}'; then
  reply "400 Bad Request" "unexpected line"
fi
[ "$(printf '%s\n' "$body" | grep -c '^uuid=')" = 1 ] || reply "400 Bad Request" "exactly one uuid"
nics=$(printf '%s\n' "$body" | grep -c '^nic=')
[ "$nics" -ge 1 ] && [ "$nics" -le 16 ] || reply "400 Bad Request" "one to 16 NICs"
uuid=$(printf '%s\n' "$body" | sed -n 's/^uuid=//p')
if [ ! -e "$dir/$uuid" ] && [ "$(ls "$dir" | wc -l)" -ge 256 ]; then
  reply "429 Too Many Requests" "too many machines announced"
fi
tmp=$(mktemp "$dir/.in.XXXXXX") || reply "500 Internal Server Error" "cannot record"
{
  printf '%s\n' "$body"
  case "$REMOTE_ADDR" in *[!0-9.]*|'') ;; *) printf 'from=%s\n' "$REMOTE_ADDR" ;; esac
  printf 'seen=%s\n' "$(date +%s)"
} >"$tmp"
mv "$tmp" "$dir/$uuid"
reply "200 OK" "recorded"
CGI
  chmod 755 "$http/cgi-bin/announce"
}

prune_announcements() {
  find "$STATE/announced" -type f -mmin +1440 -exec rm -f {} + 2>/dev/null || true
}

# Mirrors the Secret into the served tree. Files are copied rather than linked,
# so the server never follows a link out of its root.
sync_seeds() {
  wanted=" "
  for script in "$SEEDS"/*.ipxe; do
    [ -f "$script" ] || continue
    mac="$(basename "$script" .ipxe)"
    case "$mac" in
      [0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]-[0-9a-f][0-9a-f]) ;;
      *) continue ;;
    esac
    [ -f "$SEEDS/$mac.user-data" ] && [ -f "$SEEDS/$mac.meta-data" ] || continue
    wanted="$wanted$mac "
    mkdir -p "$http/hosts/$mac"
    : > "$http/hosts/$mac/vendor-data"
    changed=
    for pair in "$mac.ipxe:$mac.ipxe" "$mac.user-data:$mac/user-data" "$mac.meta-data:$mac/meta-data"; do
      src="$SEEDS/${pair%%:*}" target="$http/hosts/${pair#*:}"
      cmp -s "$src" "$target" || { cp "$src" "$target.new" && mv "$target.new" "$target" && changed=1; }
    done
    [ -z "$changed" ] || log "serving the install for $mac"
  done
  for dir in "$http/hosts"/*; do
    [ -d "$dir" ] || continue
    mac="$(basename "$dir")"
    case "$wanted" in *" $mac "*) continue ;; esac
    rm -rf "$dir" "$http/hosts/$mac.ipxe"
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
    prune_announcements
    sleep 5
  done
  log "a server exited" >&2
  return 1
}

[ "${RACK_BOOT_SOURCE_ONLY:-}" = 1 ] || serve
