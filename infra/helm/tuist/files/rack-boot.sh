#!/bin/sh
# The rack's boot server, run by the rack-boot DaemonSet on the rack's edge
# node with host networking. On the provisioning address it serves iPXE, its
# Secure Boot shim and boot.ipxe over TFTP, and over HTTP the installer's
# kernel, initrd, shim and ISO and each host's iPXE script and autoinstall
# seed. The per-host files are what the
# operator publishes to the fleet's boot Secret, mounted at $SEEDS:
# <mac>.ipxe, <mac>.user-data and <mac>.meta-data, with the MAC hyphenated,
# and <mac>.uuid, the machine's SMBIOS UUID, under which the iPXE script is
# served too. A host with nothing published gets nothing and falls through to
# its next boot entry. The ISO comes from another edge of the site when one has
# it, over the link between the edges, and each edge offers its own there.
#
# Environment: BOOT_ADDRESS, HTTP_PORT, ISO_URL, ISO_SHA256, STATE (a host
# directory kept across restarts), SEEDS, NETBOOT (iPXE and its shim).
# RACK_BOOT_SOURCE_ONLY=1 defines the functions without serving, for the tests.
set -eu

STATE="${STATE:-/var/lib/tuist-rack-boot}"
SEEDS="${SEEDS:-/etc/rack-boot/seeds}"
NETBOOT="${NETBOOT:-/usr/share/rack-netboot}"
PEER_WAIT="${PEER_WAIT:-120}"
tftp="$STATE/tftp"
http="$STATE/http"
peer="$STATE/peer"

log() { echo "rack-boot: $*"; }

# Downloads and verifies the installer ISO once per checksum, from another edge
# if one has it, and lays out what every netboot shares.
prepare() {
  rm -rf "$tftp"
  mkdir -p "$tftp" "$http/ubuntu" "$http/hosts" "$peer"
  iso="$http/ubuntu/ubuntu.iso"
  if [ "$(cat "$STATE/iso.sha256" 2>/dev/null)" != "$ISO_SHA256" ]; then
    rm -f "$iso" "$STATE/iso.sha256" "$peer/ubuntu.iso" "$peer/ubuntu.iso.sha256"
    if ! fetch_iso_from_peers "$iso.part"; then
      fetch_iso "$ISO_URL" "$iso.part" --retry 5 --retry-all-errors || return 1
    fi
    mv "$iso.part" "$iso"
    echo "$ISO_SHA256" > "$STATE/iso.sha256"
  fi
  ln -f "$iso" "$peer/ubuntu.iso"
  cp "$STATE/iso.sha256" "$peer/ubuntu.iso.sha256"
  # The kernel and initrd come from the ISO the installer then loads, so the
  # modules in its squashfs match the running kernel, and so does Ubuntu's
  # shim, which verifies that kernel under Secure Boot.
  bsdtar -xOf "$iso" casper/vmlinuz > "$http/ubuntu/vmlinuz"
  bsdtar -xOf "$iso" casper/initrd > "$http/ubuntu/initrd"
  bsdtar -xOf "$iso" EFI/boot/bootx64.efi > "$http/ubuntu/shimx64.efi"
  # iPXE's Secure Boot build: a Microsoft-signed shim that loads the iPXE
  # signed by the iPXE project beside it, named after itself.
  cp "$NETBOOT/snponly-shim.efi" "$NETBOOT/snponly.efi" "$tftp/"
  lay_out_announce
  # iPXE asks for the host's script by the MAC it booted from, then by the
  # machine's SMBIOS UUID, which AMT's network boot of a dead host needs: it
  # boots the firmware's first network entry, whichever NIC that is. A host with
  # neither returns to its firmware's next boot entry.
  cat > "$tftp/boot.ipxe" <<IPXE
#!ipxe
chain http://$BOOT_ADDRESS:$HTTP_PORT/hosts/\${mac:hexhyp}.ipxe || chain http://$BOOT_ADDRESS:$HTTP_PORT/hosts/\${uuid}.ipxe || exit 1
IPXE
}

# Fetches url to file with curl's extra options, and keeps it only if it is the
# ISO ISO_SHA256 names.
fetch_iso() {
  url="$1" out="$2"
  shift 2
  log "downloading $url"
  if ! curl -fsSL "$@" -o "$out" "$url"; then
    rm -f "$out"
    return 1
  fi
  if ! echo "$ISO_SHA256  $out" | sha256sum -c -s; then
    log "$url does not match sha256 $ISO_SHA256" >&2
    rm -f "$out"
    return 1
  fi
}

# This edge's address, with its prefix, on vrrp0: the link between the site's
# edges that their keepalived speaks over (infra/rack-switch-fleet/lib/edge.sh).
peer_address() {
  ip -o -4 addr show dev vrrp0 2>/dev/null | awk '{print $4; exit}'
}

# The link's other addresses, where the other edges are. A link wider than a
# /26 is not the edges' own.
peer_candidates() {
  addr="${1%/*}" bits="${1#*/}"
  [ "$bits" -ge 26 ] && [ "$bits" -le 30 ] || return 0
  IFS=. read -r a b c d <<EOF
$addr
EOF
  self=$(( (a << 24) | (b << 16) | (c << 8) | d ))
  size=$(( 1 << (32 - bits) ))
  base=$(( self & ~(size - 1) ))
  i=1
  while [ "$i" -lt $(( size - 1 )) ]; do
    host=$(( base + i ))
    if [ "$host" -ne "$self" ]; then
      echo "$(( (host >> 24) & 255 )).$(( (host >> 16) & 255 )).$(( (host >> 8) & 255 )).$(( host & 255 ))"
    fi
    i=$(( i + 1 ))
  done
}

# Fetches the ISO from another edge, which offers its own on the edges' link
# (serve_peer), at the rack's speed rather than the internet's. The link comes
# up with the rack-edge pod, so it is waited for up to PEER_WAIT seconds.
fetch_iso_from_peers() {
  out="$1" waited=0
  until cidr="$(peer_address)" && [ -n "$cidr" ]; do
    [ "$waited" -lt "$PEER_WAIT" ] || return 1
    sleep 5
    waited=$(( waited + 5 ))
  done
  for candidate in $(peer_candidates "$cidr"); do
    offered="$(curl -fsS --connect-timeout 3 "http://$candidate:$HTTP_PORT/ubuntu.iso.sha256" 2>/dev/null || true)"
    [ "$offered" = "$ISO_SHA256" ] || continue
    fetch_iso "http://$candidate:$HTTP_PORT/ubuntu.iso" "$out" --connect-timeout 3 && return 0
  done
  return 1
}

# Offers this edge's verified ISO, and only it, to the other edges on its
# address on the edges' link, once that is up.
serve_peer() {
  if [ -n "${peer_pid:-}" ] && kill -0 "$peer_pid" 2>/dev/null; then
    return 0
  fi
  cidr="$(peer_address)"
  [ -n "$cidr" ] || return 0
  busybox-extras httpd -f -p "${cidr%/*}:$HTTP_PORT" -h "$peer" &
  peer_pid=$!
  log "offering the ISO to the other edges on ${cidr%/*}"
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
    pairs="$mac.ipxe:$mac.ipxe $mac.user-data:$mac/user-data $mac.meta-data:$mac/meta-data"
    uuid=
    [ -f "$SEEDS/$mac.uuid" ] && uuid="$(tr -d '\n' <"$SEEDS/$mac.uuid")"
    if printf '%s\n' "$uuid" | grep -Eqx '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'; then
      pairs="$pairs $mac.ipxe:$uuid.ipxe"
      wanted="$wanted$uuid.ipxe "
    fi
    for pair in $pairs; do
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
  for alias in "$http/hosts"/????????-????-????-????-????????????.ipxe; do
    [ -f "$alias" ] || continue
    case "$wanted" in *" $(basename "$alias") "*) continue ;; esac
    rm -f "$alias"
  done
}

serve() {
  : "${BOOT_ADDRESS:?}" "${HTTP_PORT:?}" "${ISO_URL:?}" "${ISO_SHA256:?}"
  trap 'kill ${tftp_pid:-} ${http_pid:-} ${peer_pid:-} 2>/dev/null' EXIT INT TERM
  prepare
  serve_peer
  until ip -o -4 addr show | grep -q " inet $BOOT_ADDRESS/"; do
    log "waiting for $BOOT_ADDRESS, which the rack-edge pod puts on the switch port"
    serve_peer
    sleep 5
  done
  sync_seeds
  dnsmasq --no-daemon --port=0 --bind-dynamic --listen-address="$BOOT_ADDRESS" \
    --enable-tftp --tftp-root="$tftp" --log-facility=- &
  tftp_pid=$!
  busybox-extras httpd -f -vv -p "$BOOT_ADDRESS:$HTTP_PORT" -h "$http" &
  http_pid=$!
  while kill -0 "$tftp_pid" 2>/dev/null && kill -0 "$http_pid" 2>/dev/null; do
    serve_peer
    sync_seeds
    prune_announcements
    sleep 5
  done
  log "a server exited" >&2
  return 1
}

[ "${RACK_BOOT_SOURCE_ONLY:-}" = 1 ] || serve
