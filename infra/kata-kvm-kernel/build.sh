#!/usr/bin/env bash
# Builds Kata's x86_64 guest kernel exactly as kata-static does, plus kvm.conf.
# Usage: build.sh <output-dir>. Needs the kernel build dependencies installed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
out="$(mkdir -p "$1" && cd "$1" && pwd)"
# shellcheck source=release.env
. "$here/release.env"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git clone --quiet --depth 1 --branch "$KATA_VERSION" https://github.com/kata-containers/kata-containers.git "$work/kata"
kernel_dir="$work/kata/tools/packaging/kernel"
kernel_version="$(awk '/^  kernel:/ {k=1} k && /version:/ {gsub(/"/, "", $2); print $2; exit}' "$work/kata/versions.yaml")"
config_version="$(cat "$kernel_dir/kata_config_version")"
cp "$here/kvm.conf" "$kernel_dir/configs/fragments/x86_64/kvm.conf"

# The flags kata-deploy-binaries.sh passes for the default x86_64 kernel
# (confidential + measured rootfs). build-kernel.sh fails when a requested
# symbol is missing from the final .config, so a fragment that stops
# applying fails here rather than shipping a kernel without KVM.
args=(-a x86_64 -v "$kernel_version" -f -u https://cdn.kernel.org/pub/linux/kernel/v6.x/ -x -m)
(cd "$kernel_dir" && ./build-kernel.sh "${args[@]}" setup && ./build-kernel.sh "${args[@]}" build)

build_dir="$(ls -d "$kernel_dir"/kata-linux-"${kernel_version#v}"-"$config_version")"
for symbol in CONFIG_VIRTUALIZATION CONFIG_KVM CONFIG_KVM_AMD CONFIG_KVM_INTEL CONFIG_KVM_IOAPIC; do
  grep -qx "$symbol=y" "$build_dir/.config" || { echo "$symbol missing from the built kernel" >&2; exit 1; }
done

name="vmlinux-kata-kvm-$KATA_VERSION-$REVISION"
cp "$build_dir/vmlinux" "$out/$name"
cp "$build_dir/.config" "$out/$name.config"
(cd "$out" && sha256sum "$name" > "$name.sha256")
echo "built $name from kernel ${kernel_version#v}, Kata config $config_version"
cat "$out/$name.sha256"
