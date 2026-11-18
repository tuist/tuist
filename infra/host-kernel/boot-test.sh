#!/usr/bin/env bash
# Boot the packaged kernel, not a different build-tree image. This catches
# packaging/early-boot failures; physical-host qualification is a separate gate.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
package=${1:?usage: boot-test.sh <linux-image.deb>}
# shellcheck source=release.env
. "$here/release.env"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dpkg-deb -x "$package" "$work/root"
bash "$here/check-config.sh" "$work/root/boot/config-$KERNEL_VERSION-tuist$REVISION"
mkdir -p "$work/root"/{bin,proc,sys,dev,tmp}
# The kernel opens the initial console before /init can mount devtmpfs.
# Run this script as root in the disposable build/test machine only.
mknod "$work/root/dev/console" c 5 1
mknod "$work/root/dev/null" c 1 3
cp /bin/busybox "$work/root/bin/busybox"
for applet in sh mount uname modprobe test echo poweroff; do
  ln -s busybox "$work/root/bin/$applet"
done
cat > "$work/root/init" <<'INIT'
#!/bin/sh
export PATH=/bin
fail() { echo "tuist-host-kernel: FAIL $*"; poweroff -f; exit 1; }
mount -t proc proc /proc || fail proc
mount -t sysfs sysfs /sys || fail sysfs
mount -t devtmpfs devtmpfs /dev || fail devtmpfs
for module in tun xfs overlay dm_thin_pool vhost_net; do
  modprobe "$module" || fail "module $module"
done
test -c /dev/net/tun || fail tun-device
echo "tuist-host-kernel: PASS $(uname -r)"
poweroff -f
INIT
chmod 0755 "$work/root/init"
depmod -b "$work/root" "$KERNEL_VERSION-tuist$REVISION"
(cd "$work/root" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -1) > "$work/initramfs.gz"
timeout 180 qemu-system-x86_64 -accel tcg -cpu max -smp 2 -m 4096 \
  -nographic -no-reboot -nic none \
  -kernel "$work/root/boot/vmlinuz-$KERNEL_VERSION-tuist$REVISION" \
  -initrd "$work/initramfs.gz" \
  -append 'console=ttyS0 rdinit=/init panic=-1' | tee "$work/boot.log"
tr -d '\r' < "$work/boot.log" | grep -Fx "tuist-host-kernel: PASS $KERNEL_VERSION-tuist$REVISION"
