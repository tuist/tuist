#!/usr/bin/env bats
# The rack boot server's script (infra/helm/tuist/files/rack-boot.sh), sourced
# without serving: what it lays out and how it mirrors the operator's Secret.

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
  export STATE="$BATS_TEST_TMPDIR/state" SEEDS="$BATS_TEST_TMPDIR/seeds" NETBOOT="$BATS_TEST_TMPDIR/netboot"
  mkdir -p "$SEEDS" "$NETBOOT"
  echo grub >"$NETBOOT/grubx64.efi"
  RACK_BOOT_SOURCE_ONLY=1
  # shellcheck source=/dev/null
  source "$ROOT/infra/helm/tuist/files/rack-boot.sh"
  set +eu
}

publish() {
  local mac="$1" tag="$2"
  printf 'menu %s\n' "$tag" >"$SEEDS/$mac.grub.cfg"
  printf '#cloud-config %s\n' "$tag" >"$SEEDS/$mac.user-data"
  printf 'instance-id: %s\n' "$tag" >"$SEEDS/$mac.meta-data"
}

@test "a published install is served over TFTP under both names GRUB looks for, and its seed over HTTP" {
  publish 38-05-25-38-b5-b5 one
  run sync_seeds
  [ "$status" -eq 0 ]
  [[ "$output" == *"serving the install for 38-05-25-38-b5-b5"* ]]
  [ "$(cat "$STATE/tftp/grub/grub.cfg-01-38-05-25-38-b5-b5")" = "menu one" ]
  [ "$(cat "$STATE/tftp/grub/hosts/38:05:25:38:b5:b5.cfg")" = "menu one" ]
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5/user-data")" = "#cloud-config one" ]
  [ "$(cat "$STATE/http/hosts/38-05-25-38-b5-b5/meta-data")" = "instance-id: one" ]
  [ -f "$STATE/http/hosts/38-05-25-38-b5-b5/vendor-data" ]

  run sync_seeds
  [ -z "$output" ]

  publish 38-05-25-38-b5-b5 two
  sync_seeds
  [ "$(cat "$STATE/tftp/grub/hosts/38:05:25:38:b5:b5.cfg")" = "menu two" ]
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
  [ ! -e "$STATE/tftp/grub/grub.cfg-01-38-05-25-38-b5-b5" ]
  [ ! -e "$STATE/tftp/grub/hosts/38:05:25:38:b5:b5.cfg" ]
  [ "$(cat "$STATE/tftp/grub/hosts/aa:bb:cc:dd:ee:ff.cfg")" = "menu other" ]
}

@test "only a complete install under a MAC is served" {
  publish 38-05-25-38-b5-b5 one
  rm "$SEEDS/38-05-25-38-b5-b5.meta-data"
  publish ..-..-..-..-..-.. traversal
  publish AA-BB-CC-DD-EE-FF upper
  sync_seeds
  [ -z "$(ls "$STATE/http/hosts" 2>/dev/null)" ]
  [ -z "$(ls "$STATE/tftp/grub/hosts" 2>/dev/null)" ]
}

@test "prepare verifies the ISO, and lays out its shim and kernel beside the network GRUB" {
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
  ISO_URL=https://releases.example/ubuntu.iso

  ISO_SHA256=bad
  run prepare
  [ "$status" -ne 0 ]
  [ ! -e "$STATE/http/ubuntu/ubuntu.iso" ]

  ISO_SHA256=good
  run prepare
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE/tftp/ubuntu/vmlinuz")" = "extracted casper/vmlinuz" ]
  [ "$(cat "$STATE/tftp/ubuntu/initrd")" = "extracted casper/initrd" ]
  [ "$(cat "$STATE/tftp/bootx64.efi")" = "extracted EFI/boot/bootx64.efi" ]
  [ "$(cat "$STATE/tftp/grubx64.efi")" = grub ]
  grep -qx 'configfile $prefix/hosts/${net_default_mac}.cfg' "$STATE/tftp/grub/grub.cfg"
  grep -qx 'exit 1' "$STATE/tftp/grub/grub.cfg"

  run prepare
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/downloads")" -eq 2 ]
}
