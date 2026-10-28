# Borrowed encrypted volume prototype

This is an experiment, not an implemented CSI capacity mode or release image.
The shipping driver remains `ceiling-backed-v1`. See the candidate design in
[sharing-compatibility.md](../sharing-compatibility.md).

Dispatch `kura-volumes-csi-image.yml` with `borrowed_only=true`. It builds an
experiment-only Kura binary, uploads it as an artifact, and tests it in a
**disposable GitHub-hosted Linux VM**. No image is published and no hosted
staging or production storage is touched. Ordinary runtime builds never apply
`patch_runtime.rb`; it rejects source drift and requires an explicit opt-in.

The Linux integration test creates a private sparse backing file, loop device,
VG and 24 GiB thin pool with 512 KiB chunks. It wraps the actual driver's
Create/Stage/Publish/Unpublish/Unstage/Delete/Observe/Reclaim operations in a
fixture-only authenticated loopback API. Each device uses a distinct derived
fixture key. This does not exercise OpenBao or the Kubernetes ownership checks.
Normal teardown refuses to destroy backing when mounts or loops remain attached.

The runtime patch routes segment IDs to a base filesystem or named borrowed
unit, scans mounted units during startup recovery, and drains sealed segments
through the existing ring-state, eviction-index and handle cleanup. A trusted
fixture control file selects placement/drain targets. The pod-like containers
run without capabilities, with private-parent host-to-container mount propagation,
1 CPU and 768 MiB memory. Publication is deliberately tested after runtime start.
The prototype does not change the data inside segment files or replication data.
Its experimental segment identities and directory layout are **not** a supported
on-disk format; never run the patch against an existing Kura directory.

The transfer checks aim to prove that two instances keep stable base volumes
while one returns a separately backed unit and the other consumes its backing.
Logical ceilings exceed pool capacity, but existing devices remain fully backed.
Open-unlinked files, failed trim and CSI/runtime restart must retain charges
until actual deletion. The measurement compares the same experimental binary
with its opt-in disabled on shared XFS and monolithic LUKS, and enabled on
multiple LUKS volumes, in forward/reverse order using authenticated cache HTTP
requests and checksums. All have a 4 GiB cache budget; provisioned device sizes
and duplicated filesystem/workspace overhead differ and are reported. These
loop-backed VM results are not hosted NVMe or production throughput results.

## Deliberate limits

- No production allocator, fairness adaptation, budget leases or child-volume
  authorization. Existing whole-PVC identities stand in for child identities.
- The control file is a trusted test control, not a durable fenced grant API.
  Active segments seal through the normal writer barrier before targeted drain.
- No Kubernetes scheduling, mount-namespace lifecycle or actual node reboot
  qualification. Docker propagation is one necessary primitive only.
- No migration/endpoint-handoff qualification, replica workload or egress proof.
- Existing sizing is intentionally reused, including 2 GiB workspace per volume;
  this overstates useful capacity cost and is not a final multi-volume profile.
- No production claim about metadata worst-case sizing or exhaustion recovery.
  Existing conservative CSI tests and the negative fragmentation test remain.
- Source and measurement artifacts must name exact revisions. Failed attempts
  must remain in the validation record; passing primitives alone do not clear
  #14152's sharing-compatibility or production rollout gates.
