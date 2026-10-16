# kata-kvm-kernel

Kata's x86_64 guest kernel with KVM built in, for runner pools that set
`nestedVirtualization` (Android emulators). Stock Kata guest kernels set
only `CONFIG_KVM_GUEST` and have no module support, so a Kata guest can
never expose `/dev/kvm` without this kernel.

- `kvm.conf` is the only delta: `CONFIG_VIRTUALIZATION`, `CONFIG_KVM`,
  `CONFIG_KVM_AMD`, `CONFIG_KVM_INTEL`, all `=y`.
- `build.sh <out>` clones the Kata release in `release.env`, drops the
  fragment into `tools/packaging/kernel/configs/fragments/x86_64/`, and runs
  `build-kernel.sh` with the flags kata-static uses for the default x86_64
  kernel (`-x -m`). `build-kernel.sh` fails when a requested symbol is not
  in the final `.config`, and the script checks the four symbols again.
- `check-kvm.sh` runs inside a Kata container given `/dev/kvm` and creates
  a VM as root and as `nobody`.
- `.github/workflows/kata-kvm-kernel.yml` builds on PRs, verifies on a
  GitHub-hosted runner (a nested-virtualization VM) by booting a Kata
  container on the new kernel, and on `main` publishes
  `kata-kvm-kernel@<KATA_VERSION>-<REVISION>` with the kernel, its
  `.sha256` and its `.config`. A published revision is never rebuilt.

`KATA_VERSION` must match `kataVersion` in the CAPI provider
(`controllers/linux/linux_cloudinit.go`), and `kataKVMKernelRelease` in
`controllers/linux/kata_kvm.go` pins the release hosts install
(`TestKataKVMKernelMatchesKataVersion`). A Kata bump therefore means: bump
`release.env`, merge, then bump both provider constants.
