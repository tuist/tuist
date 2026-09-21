#!/usr/bin/env bash
# Bake a node's autoinstall config into a copy of the Ubuntu ISO, so the stick
# installs the machine with no keystrokes at all: no GRUB editing, and nothing
# served over the network at boot time.
# Sourced by the rack:* tasks: build_autoinstall_iso <node> <base-iso> <out-iso> <ssh-pubkey>

build_autoinstall_iso() {
  local node="$1" base_iso="$2" out_iso="$3" ssh_key="$4"
  local root workdir tree label boot_args

  root="$(git rev-parse --show-toplevel)"
  # shellcheck source=/dev/null
  source "$root/infra/rack-nodes/render-autoinstall.sh"

  if ! command -v xorriso >/dev/null; then
    echo "error: xorriso is needed to build the install image (brew install xorriso)" >&2
    return 1
  fi

  workdir="$(mktemp -d)"
  tree="$workdir/iso"

  echo "unpacking $(basename "$base_iso")" >&2
  xorriso -osirrox on -indev "$base_iso" -extract / "$tree" >/dev/null 2>&1
  chmod -R u+w "$tree"

  render_autoinstall "$node" "$tree/nocloud" "$ssh_key" || { rm -rf "$workdir"; return 1; }

  # The installer reads its config from the disc. The seed path needs its
  # trailing slash, and the semicolon is quoted so GRUB does not read it as a
  # command separator and drop everything after it.
  local grub="$tree/boot/grub/grub.cfg"
  if [ ! -f "$grub" ]; then
    echo "error: no grub.cfg in the image; its layout changed" >&2
    rm -rf "$workdir"
    return 1
  fi

  awk -v seed='autoinstall "ds=nocloud;s=/cdrom/nocloud/"' '
    /linux[[:space:]]+\/casper\/(hwe-)?vmlinuz/ { sub(/---/, seed " ---") }
    /^set timeout=/ { $0 = "set timeout=3" }
    { print }
  ' "$grub" > "$grub.new" && mv "$grub.new" "$grub"

  if ! grep -q "nocloud" "$grub"; then
    echo "error: could not add the autoinstall option to grub.cfg" >&2
    rm -rf "$workdir"
    return 1
  fi

  # Reproduce the original boot structures rather than guessing them: xorriso can
  # report the exact mkisofs arguments that recreate this image's El Torito and
  # hybrid GPT layout.
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
