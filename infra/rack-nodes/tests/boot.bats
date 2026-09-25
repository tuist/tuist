#!/usr/bin/env bats
# The rack boot server's script (infra/helm/tuist/files/rack-boot.sh), sourced
# without serving: what it lays out and how it mirrors the operator's Secret.

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
  export STATE="$BATS_TEST_TMPDIR/state" SEEDS="$BATS_TEST_TMPDIR/seeds" NETBOOT="$BATS_TEST_TMPDIR/netboot" PEER_WAIT=0
  mkdir -p "$SEEDS" "$NETBOOT"
  echo ipxe >"$NETBOOT/snponly.efi"
  echo shim >"$NETBOOT/snponly-shim.efi"
  RACK_BOOT_SOURCE_ONLY=1
  # shellcheck source=/dev/null
  source "$ROOT/infra/helm/tuist/files/rack-boot.sh"
  set +u
}

publish() {
  local mac="$1" tag="$2"
  printf '#!ipxe %s\n' "$tag" >"$SEEDS/$mac.ipxe"
  printf '#cloud-config %s\n' "$tag" >"$SEEDS/$mac.user-data"
  printf 'instance-id: %s\n' "$tag" >"$SEEDS/$mac.meta-data"
}

@test "a published install is served over HTTP: the host's iPXE script and its seed" {
  publish 38-05-25-38-b5-b5 one
  run sync_seeds
  [ "$status" -eq 0 ]
  [[ "$output" == *"serving the install for 38-05-25-38-b5-b5"* ]]
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5.ipxe")" = "#!ipxe one" ]
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5/user-data")" = "#cloud-config one" ]
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5/meta-data")" = "instance-id: one" ]
  [ -f "$STATE/http/hosts/38-05-25-38-b5-b5/vendor-data" ]

  run sync_seeds
  [ -z "$output" ]

  publish 38-05-25-38-b5-b5 two
  sync_seeds
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5.ipxe")" = "#!ipxe two" ]
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5/user-data")" = "#cloud-config two" ]
}

@test "a withdrawn install stops being served, and the others stay" {
  publish 38-05-25-38-b5-b5 one
  publish aa-bb-cc-dd-ee-ff other
  sync_seeds
  rm "$SEEDS"/38-05-25-38-b5-b5.*
  run sync_seeds
  [[ "$output" == *"withdrew the install for 38-05-25-38-b5-b5"* ]]
  [ ! -e "$STATE/http/hosts/38-05-25-38-b5-b5" ]
  [ ! -e "$STATE/http/hosts/38-05-25-38-b5-b5.ipxe" ]
  [ "$(cat "$STATE/http/hosts/aa-bb-cc-dd-ee-ff.ipxe")" = "#!ipxe other" ]
}

@test "only a complete install under a MAC is served" {
  publish 38-05-25-38-b5-b5 one
  rm "$SEEDS/38-05-25-38-b5-b5.meta-data"
  publish ..-..-..-..-..-.. traversal
  publish AA-BB-CC-DD-EE-FF upper
  sync_seeds
  [ -z "$(ls "$STATE/http/hosts" 2>/dev/null)" ]
}

# AMT boots a dead host from its network, which PXE-boots from the firmware's
# first network entry, not necessarily the NIC the install is published for,
# so the install is also served under the machine's SMBIOS UUID.
@test "a complete install is also served under the machine's UUID, and withdrawn with it" {
  publish 38-05-25-3a-de-d3 one
  echo 04450c00-63f4-11f1-81f4-3582298d5c00 >"$SEEDS/38-05-25-3a-de-d3.uuid"
  run sync_seeds
  [ "$(cat "$STATE/http/hosts/04450c00-63f4-11f1-81f4-3582298d5c00.ipxe")" = "#!ipxe one" ]

  publish 38-05-25-3a-de-d3 two
  sync_seeds
  [ "$(cat "$STATE/http/hosts/04450c00-63f4-11f1-81f4-3582298d5c00.ipxe")" = "#!ipxe two" ]

  rm "$SEEDS"/38-05-25-3a-de-d3.*
  run sync_seeds
  [ ! -e "$STATE/http/hosts/04450c00-63f4-11f1-81f4-3582298d5c00.ipxe" ]
}

@test "a UUID that is not one is not served" {
  publish 38-05-25-3a-de-d3 one
  echo "../../etc/passwd" >"$SEEDS/38-05-25-3a-de-d3.uuid"
  publish aa-bb-cc-dd-ee-ff other
  echo 04450C00-63F4-11F1-81F4-3582298D5C00 >"$SEEDS/aa-bb-cc-dd-ee-ff.uuid"
  sync_seeds
  [ -z "$(ls "$STATE/http/hosts" | grep -Ev "^(38-05-25-3a-de-d3|aa-bb-cc-dd-ee-ff)")" ]
}

@test "prepare verifies the ISO, serves its kernel and shim over HTTP and the signed iPXE over TFTP" {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat >"$bin/curl" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
echo "iso bytes" >"$out"
echo x >>"$BATS_TEST_TMPDIR/downloads"
EOF
  cat >"$bin/bsdtar" <<'EOF'
#!/bin/sh
echo "extracted $3"
EOF
  cat >"$bin/sha256sum" <<'EOF'
#!/bin/sh
read -r sum file
[ "$sum" = good ]
EOF
  chmod +x "$bin"/*
  PATH="$bin:$PATH"
  ISO_URL=https://releases.example/ubuntu.iso BOOT_ADDRESS=192.168.50.1 HTTP_PORT=8480

  ISO_SHA256=bad
  run prepare
  [ "$status" -ne 0 ]
  [ ! -e "$STATE/http/ubuntu/ubuntu.iso" ]

  mkdir -p "$STATE/tftp/grub"
  ISO_SHA256=good
  run prepare
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/http/ubuntu/vmlinuz")" = "extracted casper/vmlinuz" ]
  [ "$(cat "$STATE/http/ubuntu/initrd")" = "extracted casper/initrd" ]
  [ "$(cat "$STATE/http/ubuntu/shimx64.efi")" = "extracted EFI/boot/bootx64.efi" ]
  [ "$(cat "$STATE/tftp/snponly-shim.efi")" = shim ]
  [ "$(cat "$STATE/tftp/snponly.efi")" = ipxe ]
  grep -qx 'chain http://192.168.50.1:8480/hosts/${mac:hexhyp}.ipxe || chain http://192.168.50.1:8480/hosts/${uuid}.ipxe || exit 1' "$STATE/tftp/boot.ipxe"
  [ ! -e "$STATE/tftp/grub" ]

  run prepare
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/downloads")" -eq 2 ]
}

# A freshly installed edge fetches the ISO from another edge over the link the
# edges' keepalived speaks over, at the rack's own speed, and from the internet
# only when no edge has it.
edge_link() {
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  cat >"$bin/ip" <<'EOF'
#!/bin/sh
case "$*" in
  "-o -4 addr show dev vrrp0") echo "8: vrrp0    inet 10.255.255.2/29 scope global vrrp0" ;;
esac
EOF
  # The other edge at .1 offers the ISO its checksum file names; nothing
  # answers at the link's other addresses.
  cat >"$bin/curl" <<'EOF'
#!/bin/sh
out=
while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; -*) shift;; *) url="$1"; shift;; esac; done
echo "$url" >>"$BATS_TEST_TMPDIR/fetched"
case "$url" in
  http://10.255.255.1:8480/ubuntu.iso.sha256) echo "${PEER_SUM:-good}" ;;
  http://10.255.255.1:8480/ubuntu.iso) echo "${PEER_ISO:-iso bytes}" >"$out" ;;
  http://10.255.255.*) exit 7 ;;
  *) echo "iso bytes" >"$out" ;;
esac
EOF
  cat >"$bin/bsdtar" <<'EOF'
#!/bin/sh
echo "extracted $3"
EOF
  cat >"$bin/sha256sum" <<'EOF'
#!/bin/sh
read -r sum file
[ "$sum" = good ] && ! grep -q corrupt "$file"
EOF
  chmod +x "$bin"/*
  PATH="$bin:$PATH"
  ISO_URL=https://releases.example/ubuntu.iso ISO_SHA256=good BOOT_ADDRESS=192.168.50.1 HTTP_PORT=8480
}

@test "a fresh edge fetches the ISO from another edge over the edges' link, not the internet" {
  edge_link
  run prepare
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/http/ubuntu/ubuntu.iso")" = "iso bytes" ]
  grep -qx "http://10.255.255.1:8480/ubuntu.iso" "$BATS_TEST_TMPDIR/fetched"
  [ -z "$(grep -e releases.example -e 10.255.255.2: "$BATS_TEST_TMPDIR/fetched")" ]
}

@test "an edge whose ISO is another release, or does not verify, is passed over for the internet" {
  edge_link
  export PEER_SUM=other
  run prepare
  [ "$status" -eq 0 ]
  [ -z "$(grep -x http://10.255.255.1:8480/ubuntu.iso "$BATS_TEST_TMPDIR/fetched")" ]
  grep -qx "https://releases.example/ubuntu.iso" "$BATS_TEST_TMPDIR/fetched"

  rm -rf "$STATE" "$BATS_TEST_TMPDIR/fetched"
  export PEER_SUM=good PEER_ISO=corrupt
  run prepare
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/http/ubuntu/ubuntu.iso")" = "iso bytes" ]
  grep -qx "https://releases.example/ubuntu.iso" "$BATS_TEST_TMPDIR/fetched"
}

@test "an edge offers the other edges its verified ISO, and nothing else, on its own link address" {
  edge_link
  cat >"$bin/busybox-extras" <<'EOF'
#!/bin/sh
echo "$@" >"$BATS_TEST_TMPDIR/httpd"
EOF
  chmod +x "$bin/busybox-extras"
  prepare
  [ "$(ls "$STATE/peer" | tr '\n' ' ')" = "ubuntu.iso ubuntu.iso.sha256 " ]
  [ "$(cat "$STATE/peer/ubuntu.iso.sha256")" = good ]
  [ "$STATE/peer/ubuntu.iso" -ef "$STATE/http/ubuntu/ubuntu.iso" ]

  serve_peer
  wait
  [ "$(cat "$BATS_TEST_TMPDIR/httpd")" = "httpd -f -p 10.255.255.2:8480 -h $STATE/peer" ]
}

# A machine whose stick finds no install published announces itself, so the
# operator can list it as a candidate host instead of someone reading its MAC.
announce() {
  local body="$1" method="${2:-POST}"
  printf '%s' "$body" | env REQUEST_METHOD="$method" CONTENT_LENGTH="${#body}" REMOTE_ADDR=192.168.50.144 \
    "$STATE/http/cgi-bin/announce"
}

ms01='uuid=44312e80-1dc6-11f1-853e-8f903547d200
serial=MD148LS139QQMQE00070
product=Micro Computer (HK) Tech Limited Venus Series
nic=38:05:25:38:b5:b5 igc 0x125b
nic=38:05:25:38:b5:b4 igc 0x125c
nic=38:05:25:38:b5:b2 i40e 0x1572'

@test "the boot server records a machine's announcement under its UUID" {
  lay_out_announce
  [ -x "$STATE/http/cgi-bin/announce" ]
  run announce "$ms01"
  [ "$status" -eq 0 ]
  [[ "$output" == "Status: 200"* ]]
  recorded="$STATE/announced/44312e80-1dc6-11f1-853e-8f903547d200"
  [ "$(grep -c '^nic=' "$recorded")" = 3 ]
  grep -qx 'serial=MD148LS139QQMQE00070' "$recorded"
  grep -qx 'from=192.168.50.144' "$recorded"
  grep -qE '^seen=[0-9]+$' "$recorded"
}

@test "an announcement that is not exactly the expected lines is refused" {
  lay_out_announce
  for bad in \
    "$(printf '%s\nnic=38:05:25:38:b5:b5 igc 0x125b; rm -rf /\n' "$ms01")" \
    "$(printf 'uuid=../../etc/passwd\nnic=38:05:25:38:b5:b5 igc 0x125b\n')" \
    "$(printf 'serial=only\n')" \
    "$(printf '%s\n%s\n' "$ms01" "uuid=00000000-0000-0000-0000-000000000000")" \
    "$(printf '%s\nhostname=evil\n' "$ms01")"; do
    run announce "$bad"
    [[ "$output" == "Status: 400"* ]]
  done
  run announce "$ms01" GET
  [[ "$output" == "Status: 405"* ]]
  run announce "$(printf '%s\nproduct=%05000d\n' "$ms01" 0)"
  [[ "$output" == "Status: 413"* ]]
  [ -z "$(ls "$STATE/announced")" ]
}

@test "the boot server keeps at most 256 machines, and refreshes one it knows" {
  lay_out_announce
  for i in $(seq 1 256); do : >"$STATE/announced/$(printf '00000000-0000-0000-0000-%012d' "$i")"; done
  run announce "$ms01"
  [[ "$output" == "Status: 429"* ]]
  rm "$STATE/announced/00000000-0000-0000-0000-000000000001"
  run announce "$ms01"
  [[ "$output" == "Status: 200"* ]]
  run announce "$ms01"
  [[ "$output" == "Status: 200"* ]]
}

@test "announcements older than a day are dropped" {
  lay_out_announce
  announce "$ms01" >/dev/null
  : >"$STATE/announced/00000000-0000-0000-0000-000000000001"
  touch -t 202601010000 "$STATE/announced/00000000-0000-0000-0000-000000000001"
  prune_announcements
  [ -f "$STATE/announced/44312e80-1dc6-11f1-853e-8f903547d200" ]
  [ ! -e "$STATE/announced/00000000-0000-0000-0000-000000000001" ]
}
