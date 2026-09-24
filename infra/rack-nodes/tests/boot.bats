#!/usr/bin/env bats
# The rack boot server's script (infra/helm/tuist/files/rack-boot.sh), sourced
# without serving: what it lays out and how it mirrors the operator's Secret.

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
  export STATE="$BATS_TEST_TMPDIR/state" SEEDS="$BATS_TEST_TMPDIR/seeds" NETBOOT="$BATS_TEST_TMPDIR/netboot"
  mkdir -p "$SEEDS" "$NETBOOT"
  echo ipxe >"$NETBOOT/snponly.efi"
  RACK_BOOT_SOURCE_ONLY=1
  # shellcheck source=/dev/null
  source "$ROOT/infra/helm/tuist/files/rack-boot.sh"
  set +eu
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

@test "prepare verifies the ISO, serves its kernel over HTTP and iPXE over TFTP" {
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
  [ "$(cat "$STATE/tftp/snponly.efi")" = ipxe ]
  grep -qx 'chain http://192.168.50.1:8480/hosts/${mac:hexhyp}.ipxe || exit 1' "$STATE/tftp/boot.ipxe"
  [ ! -e "$STATE/tftp/grub" ]

  run prepare
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/downloads")" -eq 2 ]
}
