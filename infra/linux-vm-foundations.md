# Linux VM foundations for runners and sandboxes

Status: decision record, 2026-11-16. Covers the Linux fleet only; macOS runs
both products on Tart through tart-kubelet and is out of scope.

Linux CI runners ([runners-controller](runners-controller/AGENTS.md),
[linux-runner-image](linux-runner-image/AGENTS.md)) and agent sandboxes
([sandboxd](sandboxd/AGENTS.md), [sandbox-image](sandbox-image/AGENTS.md))
should share image preparation, node storage, distribution and hosts, so a
customer's setup is paid once and reused by CI jobs, Amp Orbs, Claude Code
sessions and remote execution. They should not be forced onto one hypervisor
or one lifecycle to get there.

## Decision

1. **Keep two runtimes for now.** One-job CI runners stay Kata + QEMU Pods.
   Persistent agent sessions and remote-execution actions stay Firecracker
   VMs under sandboxd. Kata is not replaced, and CI is not moved onto
   Firecracker or onto sandboxd.
2. **Converge below and above the hypervisor**: guest image content and
   its build, disk-image formats and the node store, object-storage
   distribution, placement, host admission and the guest kernel build.
3. **Cloud Hypervisor is the only candidate for one VMM**, because it is the
   only one that could plausibly meet both columns of the table below. It is
   an evaluation with gates (step 5 below), not a plan, and none of its
   capabilities in that table have been verified on our hosts.

The VMM is not where customers lose time today. In production, a sandbox
created from the template snapshot boots in 147 ms at p50, while a spawn that
misses its node's disk snapshot spends 44 s at p50 downloading a 4.4 GB
archive, and one that falls back to the template reruns setup for 411 s at
p50 ([measured latency](sandboxd/AGENTS.md#measured-latency)). Prepared
state and its distribution are the shared problem; the hypervisor is not.

## Why not one hypervisor now

Requirements the products already depend on. "Verified" means exercised on
our hosts by the cited validation; everything else is a documented or
expected property that has not been tested here.

| Requirement | Today | Kata + QEMU | Firecracker | Cloud Hypervisor |
|---|---|---|---|---|
| CI container rootfs from containerd's overlay snapshot | kata-qemu over virtio-fs | verified (production) | no virtio-fs or 9p; `kata-fc` needs a block snapshotter ([substrate](runners-controller/AGENTS.md#linux-runner-substrate-ovh-bare-metal-boxes-kata-qemu)) | virtio-fs supported; `kata-clh` untested here |
| Host cache volumes and checkouts bind-mounted into the job | mount propagation through Kata | verified (staging and production) | would need one block device per volume, fixed before boot or snapshot | virtio-fs; untested |
| Docker: privileged DinD sidecar, service and `container:` jobs, Docker cache image loop-mounted in the guest | Kata guest kernel | verified | sandbox guest has no Docker and its Firecracker CI kernel is untested for it | depends on the guest kernel; untested |
| Nested KVM for Android emulators | kata-kvm-kernel, device plugin | verified 2026-10-27 (`android-smoke`) | not validated; treat as unsupported until proven | expected; untested |
| Exclusive CPUs | kubelet pod-level resource managers | verified | sandboxd VMs are not Pods; would need its own pinning | same as QEMU through `kata-clh` |
| Claims, billing, reconcile, drain by Pod lifecycle | runners-controller and server | in production | would need a new control plane | kept through `kata-clh` |
| Restore a session from a per-shape template snapshot, pause to disk, lazy memory restore from object storage (userfaultfd), lazy disks | sandboxd | not available in this form | in production | snapshot/restore exists upstream; lazy restore parity unknown |
| Hundreds of ms create and resume | sandboxd | Kata cold boot per Pod | 147 ms p50 create, 144 ms p50 resume | unmeasured |

Each runtime is the only one verified for one column. A single VMM would
first have to pass the other column's rows on our hosts.

## Already shared

- **Hosts and admission.** sandboxd runs as a DaemonSet on the Kata runner
  nodes. CI and sandboxes share memory through per-node grants, with claimed
  jobs and active turns protected ([fleet sharing](sandboxd/fleet-sharing.md)).
- **Checkouts.** The node's runner-cache agent seeds sandbox workspaces from
  CI checkout masters, and `sbx-worker` exports commits in CI's export
  format (`sandboxd/internal/checkout`, `sandbox-image/cmd/sbx-worker/checkout.go`).
- **Placement.** Sandbox disk-snapshot copies are placed with
  `Tuist.Runners.VolumePlacement`, the same weighted rendezvous placement as
  runner cache volumes.
- **Distribution trust model.** Both node daemons move objects through
  server-signed URLs and never hold storage credentials.
- **Node filesystem.** Both use reflink clones of ext4 images on `/data`
  (XFS), with no byte-copy fallback.

## Still separate, and should converge

1. **Guest image preparation.** Two Dockerfiles assemble Ubuntu 24.04 guests
   independently, now from the same digest-pinned base that Renovate updates
   as one group. A test in `sbx-worker` fails when the Claude Code pins in the
   sandbox image, `claude-code-runners` and tart-kubelet drift apart. Only
   sandbox-image turns a filesystem tree into a bootable ext4 disk (its
   `rootfs` stage). Target: one toolchain manifest, and one tree-to-disk step
   that any guest image can use.
2. **Disk-image codec and node store.** Runner cache masters use
   `TCVSPRS1` (`runner-cache/archive.go`); sandbox archives use `SBXARC1`
   (`sandboxd/pkg/archive`, which macOS sandboxes also use). Both are zstd
   streams of the same non-zero extents, which both now find with
   `runner-cache/sparse` (`SEEK_DATA`/`SEEK_HOLE`, 128 KiB zero runs). Only the
   framing differs. Eviction, admission and disk budgets are still per service
   ([Disk and CPU](sandboxd/fleet-sharing.md#disk-and-cpu)). Target: one node
   store of lineages, masters and clones with one disk budget.
3. **Prepared state across products.** CI to sandbox exists only for
   checkouts. The Docker cache is already an ext4 image the guest mounts
   itself, so it does not depend on the VMM. Generic cache volumes are host
   directories shared over virtio-fs, so a Firecracker guest would need them
   as drives. Sandbox setup snapshots (Amp disk snapshots, Claude Code
   repository snapshots) cannot serve Kata CI, whose rootfs is an overlay
   snapshot rather than a disk. Amp and Claude Code snapshots are disk
   snapshots of the same template, but Amp chooses its snapshot ids and runs
   its own setup, so sharing them is a product decision, not a storage one.
4. **Guest kernels.** CI boots Kata's kernel with a KVM fragment
   (`kata-kvm-kernel`). Sandboxes boot the Firecracker CI 6.1 kernel. One
   kernel build with a configuration per VMM would let fixes and features
   land once.

## Kept product-specific

- **Lifecycle.** CI is one job per Pod: container exit is the terminal
  signal, rollouts replace idle Pods only, and draining waits for claimed
  jobs. Sandboxes are persistent: pause, archive, resume elsewhere. sandboxd's
  shutdown stops workers and pauses VMs, and a VM still running when its
  daemon Pod goes away is lost and cold boots later. Neither is acceptable for a CI job.
- **Trust.** CI's pool-scoped dispatch token stays in the poller and metrics
  sidecars, outside the customer-controlled runner container. Sandboxes
  authenticate through the node daemon and workload identity. In both, the
  guest is untrusted and credentials stay outside customer-controlled
  images.
- **Control planes, billing and claims.** `Tuist.Runners` and
  `Tuist.Sandboxes` keep their own models; only capacity is shared.
- **Guest agents.** The Actions, Buildkite and GitLab runners and
  `tuist-job-runner` on one side; `sbx-init`, `sbx-agent` and `sbx-worker` on
  the other.

## Sequence

Each step is independent and reversible. The steps that need a decision say
so.

1. **Align guest content.** Pin the sandbox guest to the runner's Ubuntu
   digest and group their Renovate updates, and give the Claude Code pin one
   source. Low risk, and it keeps native caches built in CI valid in
   sandboxes.
2. **One disk-image codec.** Done as one extent codec, two framings. Both
   writers use `runner-cache/sparse`. The wire formats stay because they
   differ only where a product needs them to: `SBXARC1` carries several
   files, a JSON header, memory frames and lazy-disk indexes, and `TCVSPRS1`
   is the single-image object whose archive digest the cache's publication
   protocol checks. Both already store the same extents in zstd, so one
   framing would save neither space nor time, and either migration would
   need a second reader until objects expire. Results, from real ext4 images
   (an 8 GiB workspace holding 2.1 GiB, including a file of 64 KiB written
   runs between 192 KiB of zeros) on an XFS reflink loop:
   - `TCVSPRS1`: the new writer's archive is byte-identical to the old one
     (same SHA-1 inventory and SHA-256 digest). Both readers restore it
     identically. Publication and fences did not change.
   - `SBXARC1`: sandboxes now skip zero runs at 128 KiB instead of 1 MiB.
     Stored bytes fell from 2.150 GB to 1.881 GB, and a restored workspace
     allocates 1.75 GiB instead of 2.0 GiB. The compressed object stayed
     about 650 MB. The old reader extracts the new archives and the new
     reader the old ones, byte-identical, so a rollback is safe. Single runs
     wrote in 2.8 s (was 3.1 s) and restored in 2.3 to 2.5 s (was 2.8 to
     2.9 s).
   - Not a VM run: no guest booted from a restored disk.

   sandboxd's image tag now follows `runner-cache/sparse` and
   `runner-cache/go.mod` too (`sandboxd-image-version.sh`), so a change
   there restarts sandboxd on every node like any daemon change.
3. **CI-parity sandbox template** (needs a decision). A sandboxd template
   whose content is the runner image plus the sandbox guest binaries, so an
   agent can reproduce a CI job in the same environment. Open questions:
   template size (the Android SDK) and how sessions choose it. The sandbox
   `user` is UID/GID 1000 like the runner's `runner`, so CI-written caches
   and checkouts keep their ownership in sandboxes; REAPI actions run as
   `builder` (2000). Runner Pods' token holders (poller, metrics, shell)
   run the Tuist-owned `sidecar` image, so a job image can be replaced
   without handing it the dispatch token.
4. **CI caches as sandbox drives** (needs a decision). Attach read-only
   clones of a repository's runner cache masters to sandboxes as drives.
   This needs a drive slot in the template snapshot and a server rule that
   agent sessions never publish to CI lineages.
5. **Cloud Hypervisor evaluation** (needs a decision and hardware). A
   `kata-clh` RuntimeClass on one staging pool, gated on the
   `android-smoke` fixture, DinD and Docker cache jobs, cache-volume mount
   propagation, exclusive CPUs, boot p50 and p95, and per-Pod overhead
   against kata-qemu's 2560 MiB. Separately, a sandboxd prototype measured
   against the latency table above. Converge only if both pass.

Rejected for now: running simple CI jobs (no Docker, no KVM) on sandboxd's
Firecracker VMs. It would split one product across two runtimes, two claim
and billing paths and two drain models, while the cost customers see is
setup and distribution. The earlier 6 to 10 engineer-week parity estimate
was never measured and is not a basis for planning.

## Validation behind this record

- The requirements and "already shared" sections come from the cited code
  and guidance, not from new runs. No VM was booted while writing this, and
  nothing ran on staging: the orb has no KVM.
- The record checked one hypothesis on a real kernel, not in a VM: whether
  sandboxd's archive restore, which writes whole disks and syncs only at the
  end, could build up the dirty pages that once got runner-cache's agent
  OOM-killed. sandboxd's restores are charged to the daemon Pod's cgroup,
  next to its VMs. Test: `archive.Extract` restored 1.5 GiB of random data
  (a 4 GiB sparse workspace) in a cgroup v2 with `memory.max` 768 MiB, while
  another process in the same cgroup held 512, 700 or 740 MiB of anonymous
  memory, as guests would. On ext4 (Linux 6.1), dirty plus writeback pages
  peaked at 36, 12 and 20 MiB. There was no OOM kill, and each restore took
  2.0 to 2.7 s. On XFS backed by a loop file, the 700 MiB run peaked at
  16 MiB with no OOM; the 740 MiB run failed with loop-device writeback I/O
  errors, an artifact of the loop backing file being charged to the same
  cgroup. Production `/data` is not loop-backed. The kernel's per-cgroup
  dirty throttling bounded the restore, so nothing changed.
