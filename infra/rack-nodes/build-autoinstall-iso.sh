#!/usr/bin/env bash
# Bakes an autoinstall seed into a copy of the Ubuntu ISO, so the stick installs
# the machine with no keystrokes: no GRUB editing and nothing served over the
# network at boot.
# Sourced: build_autoinstall_iso <base-iso> <out-iso> <seed-dir>

build_autoinstall_iso() {
  local base_iso="$1" out_iso="$2" seed="$3"
  local workdir tree label boot_args grub

  if ! command -v xorriso >/dev/null; then
    echo "error: xorriso is needed to build the install image (brew install xorriso)" >&2
    return 1
  fi

  workdir="$(mktemp -d)"
  tree="$workdir/iso"

  echo "unpacking $(basename "$base_iso")" >&2
  xorriso -osirrox on -indev "$base_iso" -extract / "$tree" >/dev/null 2>&1
  chmod -R u+w "$tree"
  mkdir -p "$tree/nocloud"
  cp "$seed"/user-data "$seed"/meta-data "$seed"/vendor-data "$tree/nocloud/"

  # The seed path needs its trailing slash, and the semicolon is quoted so GRUB
  # does not read it as a command separator and drop everything after it.
  grub="$tree/boot/grub/grub.cfg"
  if [ ! -f "$grub" ]; then
    echo "error: no grub.cfg in the image; its layout changed" >&2
    rm -rf "$workdir"
    return 1
  fi
  awk -v seed='autoinstall "ds=nocloud;s=/cdrom/nocloud/"' '
    /linux[[:space:]]+\/casper\/(hwe-)?vmlinuz/ { sub(/---/, seed " ---") }
    /^set timeout=/ { $0 = "set timeout=3" }
    { print }
  ' "$grub" >"$grub.new" && mv "$grub.new" "$grub"
  if ! grep -q "nocloud" "$grub"; then
    echo "error: could not add the autoinstall option to grub.cfg" >&2
    rm -rf "$workdir"
    return 1
  fi

  # xorriso reports the mkisofs arguments that recreate this image's El Torito
  # and hybrid GPT layout.
  boot_args="$(xorriso -indev "$base_iso" -report_el_torito as_mkisofs 2>/dev/null | tr '\n' ' ')"
  if [ -z "$boot_args" ]; then
    echo "error: could not read the boot layout of $base_iso" >&2
    rm -rf "$workdir"
    return 1
  fi
  label="$(xorriso -indev "$base_iso" -pvd_info 2>/dev/null | awk -F"'" '/Volume Id/{print $2}')"
  [ -n "$label" ] || label="Ubuntu autoinstall"

  echo "building $(basename "$out_iso")" >&2
  (
    cd "$(dirname "$base_iso")" || exit 1
    eval xorriso -as mkisofs -r -V "'${label}'" "$boot_args" \
      -o "'$out_iso'" "'$tree'" >/dev/null 2>&1
  ) || {
    echo "error: building the install image failed" >&2
    rm -rf "$workdir"
    return 1
  }
  rm -rf "$workdir"
}
