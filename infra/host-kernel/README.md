# Linux host kernel

Build and qualification path for the x86 hosts running untrusted Firecracker
and Kata guests. This is **not** Kata's guest kernel in `../kata-kvm-kernel`.

The candidate is kernel.org **6.18.62 LTS**, containing the
[CVE-2026-99999 fix](https://github.com/torvalds/linux/commit/6785011f8b16abf40b1e9d8b2e332232b3e68822).
Ubuntu still lists Noble's 6.8.0-149 fix as work in progress as of 2026-11-07.
6.18 is also a Firecracker-supported host line. Guest boot arguments are not
a mitigation: guest root can undo them.

## Build

`.github/workflows/host-kernel.yml` builds on pull requests, boots the resulting
package in QEMU, and publishes `host-kernel@<KERNEL_VERSION>-<REVISION>` on main.
Publication does not install the kernel or change fleet configuration.

`release.env` pins the upstream source hash and full stable-signing-key
fingerprint, plus the Ubuntu modules package whose `/boot/config-*` is the
base. `host.conf` retains that distribution's driver coverage while requiring
KVM, storage, cgroup and Cilium/BPF interfaces. `check-config.sh` checks the
**resolved** configuration, so unavailable/dependency-disabled symbols fail the
build. Ubuntu-only certificate paths are cleared. The packages are unsigned:
the upstream source signature is not a Secure Boot signature.

On Ubuntu 24.04 amd64, with the dependencies from the workflow installed:

```bash
bash infra/host-kernel/build.sh out
sudo bash infra/host-kernel/boot-test.sh out/linux-image-*.deb
```

`build.sh out --configure-only` verifies both downloads, the upstream signature,
the fix marker and the resolved configuration without compiling packages.
Cross-configuration on arm64 needs `CROSS_COMPILE=x86_64-linux-gnu-` and that
compiler installed. This is not a substitute for the full amd64 build/boot.

Release contents are the image (including modules), headers, final config,
input pins and `SHA256SUMS`. Never replace an existing release's assets: bump
`REVISION`. QEMU proves early boot and the required loadable modules, not host
hardware, nested virtualization, Cilium networking or production workloads.

## Canary before activation

Do not wire an unqualified kernel into `linux_cloudinit.go` or the Ready-node
drift path. A bootstrap pin reaches newly adopted hardware; a drift installer
can change the next boot of every live host. Neither is safe merely because
the source contains the security fix. The kernel is not remediating a host
until that host **boots it**.

1. Obtain approval to publish the candidate and to operate on the one canary
   `runners-linux` host. Canary/production mutations require human elevation
   as described in `../AGENTS.md`; never retrieve an admin kubeconfig or a
   cluster Secret as a workaround.
2. Record its Node/BootID, `uname -r`, root/md/NVMe/network drivers, current GRUB
   default and working out-of-band console/recovery path. Run `mokutil
   --sb-state`. If Secure Boot is enabled, stop: the candidate needs a trusted
   signing/enrollment path, not disabling validation in an install script.
3. Cordon and wait for active runner jobs to finish. Pause sandboxes through
   sandboxd's graceful shutdown before draining/rebooting. A Kubernetes drain
   alone does not pause Firecracker VMs. Do not delete the Machine: its release
   path wipes the host. Inventory local cache volumes before eviction.
4. Download the exact release, verify `SHA256SUMS`, and install only its image
   and headers with `apt-get install ./linux-image-*.deb ./linux-headers-*.deb`.
   Keep the existing Ubuntu image/modules and GRUB entry. Check that the initrd
   contains the host's root/md and network modules. Record the new GRUB entry
   and use `grub-reboot` for a one-shot boot rather than making an untested
   kernel the permanent default. Reboot only in the approved window.
5. Verify the new BootID, exact `6.18.62-tuist1` kernel, Node Ready, Cilium and
   vRack paths, XFS quotas, thin volumes and runner-cache agent. Verify
   `KataRuntimeReady`, current-boot `KataKVMReady`/`tuist.dev/kata-kvm`, and
   an ordinary and nested-KVM Kata runner. Exercise sandbox create, exec,
   pause and resume. Run canary runners acceptance, including the Docker-cache
   cross-job probes. An old Node label is not a current-boot proof.
6. Only after all gates pass, set the tested entry as the persistent GRUB
   default, uncordon, and record the evidence. On failure leave the host cordoned,
   boot the retained Ubuntu entry through the console and verify recovery;
   do not spread the candidate to other hosts.

## After canary qualification

The follow-up provider change must checksum-verify this exact immutable release
at **new-host bootstrap**, boot it before admitting workloads, and report
running-kernel drift on existing hosts as a condition/metric without autonomous
reboots. Add the matching `kube_node_info{kernel_version}` alert. Do not hold
Ubuntu kernel metapackages before there is a qualified replacement and an
explicit policy for future security updates.

Production is an approved one-host-at-a-time wave: finish jobs, pause sandboxes,
drain, install, one-shot boot, qualify, persist, uncordon. Keep the two hosts
carrying `remote-execution-workers` last; that DaemonSet is OnDelete and needs
explicit pod replacement to pick up the template-ownership hardening release.
Verify root-owned template files and `kernel.io_uring_disabled=1` through an
approved host-inspection path, not merely from the desired ConfigMap/hash.
Include staging and rack Linux guest-running hosts in the exposure inventory;
Tart on macOS is outside this Linux-kernel fix.
