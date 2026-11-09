#!/usr/bin/env bash
# Build on Ubuntu 24.04 amd64. --configure-only checks inputs and Kconfig only.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="$(mkdir -p "${1:?usage: build.sh <out> [--configure-only]}" && cd "$1" && pwd)"
mode=${2:-}
case "$mode" in ''|--configure-only) ;; *) echo "Unknown mode: $mode" >&2; exit 1 ;; esac
# shellcheck source=release.env
. "$here/release.env"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 0700 "$GNUPGHOME"

curl -fLsS -o "$work/linux.tar.xz" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
echo "$KERNEL_SHA256  $work/linux.tar.xz" | sha256sum -c -
curl -fLsS -o "$work/linux.tar.sign" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.sign"
curl -fLsS -o "$work/signer.asc" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${KERNEL_SIGNER}"
gpg --batch --import "$work/signer.asc"
# An isolated keyring plus a full-fingerprint selection pins the signer, not
# whatever other key a keyserver happens to return. Signatures cover the tar.
gpg --batch --export "$KERNEL_SIGNER" > "$work/stable.gpg"
xz -dc "$work/linux.tar.xz" > "$work/linux.tar"
gpgv --keyring "$work/stable.gpg" "$work/linux.tar.sign" "$work/linux.tar"
tar -xf "$work/linux.tar" -C "$work"
src="$work/linux-$KERNEL_VERSION"

curl -fLsS -o "$work/base.deb" "https://security.ubuntu.com/ubuntu/pool/main/l/linux/$UBUNTU_MODULES"
echo "$UBUNTU_MODULES_SHA256  $work/base.deb" | sha256sum -c -
dpkg-deb -x "$work/base.deb" "$work/base"
cp "$work/base/boot/config-6.8.0-147-generic" "$src/.config"

# CVE-2026-99999: refuse a source tree lacking the fixed output-path checks.
grep -q 'ip_check_csum_start' "$src/net/ipv4/ip_output.c"
(
  cd "$src"
  export ARCH=x86
  scripts/kconfig/merge_config.sh -m .config "$here/host.conf"
  scripts/config --set-str LOCALVERSION "-tuist$REVISION"
  make olddefconfig
  bash "$here/check-config.sh" .config
  test "$(make -s kernelrelease)" = "$KERNEL_VERSION-tuist$REVISION"
  cp .config "$out/config-$KERNEL_VERSION-tuist$REVISION"
  if [ "$mode" != --configure-only ]; then
    # Keep debug packages out of the release; BTF remains in the kernel.
    export KDEB_COMPRESS=xz
    export DEB_BUILD_PROFILES=pkg.linux-upstream.nokerneldbg
    make -j"$(nproc)" bindeb-pkg KDEB_PKGVERSION="$KERNEL_VERSION-$REVISION" \
      KBUILD_BUILD_USER=tuist KBUILD_BUILD_HOST=host-kernel \
      KBUILD_BUILD_TIMESTAMP='2026-11-06 00:00:00 UTC' \
      KBUILD_DEBARCH=amd64
    cp "$work/linux-image-$KERNEL_VERSION-tuist${REVISION}_"*.deb "$out/"
    cp "$work/linux-headers-$KERNEL_VERSION-tuist${REVISION}_"*.deb "$out/"
  fi
)
cp "$here/release.env" "$out/release.env"
(
  cd "$out"
  files=(config-* release.env)
  if [ "$mode" != --configure-only ]; then files+=(./*.deb); fi
  sha256sum "${files[@]}" > SHA256SUMS
)
