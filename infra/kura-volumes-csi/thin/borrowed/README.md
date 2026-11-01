# Borrowed encrypted volume prototype

This is an opt-in CSI child-volume prototype with an experiment-only runtime.
The driver remains `ceiling-backed-v1`; every existing child device is fully
backed. Ordinary runtime builds and hosted enrollment do not enable it, and the
shipping CSI driver does not contain it: its implementation and tests build only
with `-tags kuraborrowed`, which the qualification jobs pass. Without the tag the
driver refuses `borrowed_units`, the units API and any borrowed volume record.
Measurements, failed attempts and qualification limits are recorded in
[validation.md](validation.md). See the candidate design in
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
through the existing ring-state, eviction-index and handle cleanup. A root-owned
control file written by CSI selects placement/drain targets. The pod-like containers
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
requests and checksums. The latest comparison adds thick monolithic and thick
multi-volume controls: all have a 4 GiB cache budget and 13 GiB aggregate virtual
size. Filesystem/workspace overhead still differs and is reported. These
loop-backed VM results are not hosted NVMe or production throughput results.

## Deliberate limits

- No production allocator, fairness adaptation or runtime budget leases. The
  fenced CSI API and server parent-PVC authorization passed the isolated
  Kubernetes/OpenBao fixture recorded in the validation report.
- Active segments seal through the normal writer barrier before targeted drain.
- Kubernetes hot publication, CSI pod restart and cold runtime-pod replacement
  passed on Paris staging. Actual node reboot/power-loss qualification is separate.
- No migration/endpoint-handoff qualification, replica workload or egress proof.
- Existing sizing is intentionally reused, including 2 GiB workspace per volume;
  this overstates useful capacity cost and is not a final multi-volume profile.
- No production claim about metadata worst-case sizing or exhaustion recovery.
  Existing conservative CSI tests and the negative fragmentation test remain.
- Source and measurement artifacts must name exact revisions. Failed attempts
  must remain in the validation record; passing primitives alone do not clear
  #14152's sharing-compatibility or production rollout gates.

## Child lifecycle contract

An explicitly created thin parent with `borrowed_units: v1` owns `base/`,
`units/` and root-owned `control.json`. The runtime writes only inside `base/`
and each child's `segments/`. Child IDs are
`pvc-<parent UUID>-unit-<unit UUID>`; their passphrase derivation and sealed-response
AAD use the entire ID. The server authorizes the live parent PV/PVC, requires
its immutable `borrowed_units: v1` attribute, and retains the existing caller
audience, node affinity, PVC UID and account-ownership checks. Children share
the account's OpenBao-wrapped shares but never share a volume passphrase.

The existing root-only allocator socket accepts `POST /v1/units`. Requests carry
the parent `volume_id`, `lv_uuid`, `pool_uuid`, `pod_uid`, `generation`, a unique
`operation_id`, immutable `unit_id`, and an action:

- `create` adds `cache_bytes`, using the conservative sizing profile. CSI
  records intent, creates/encrypts/stages/publishes the child, then advertises it.
- `drain` removes the child from placement and asks the runtime to retire its
  segments. This releases no commitment or physical-capacity credit.
- `release` requires the verified child mount's segment directory to be empty,
  then normally unpublishes, unstages, closes and deletes it. Busy descriptors
  retain the charge. The response is a fresh authoritative pool observation.
- `abort` cancels an incomplete, never-advertised create. It cannot discard an
  active child. Any partial device still passes normal detach/delete checks.

One durable operation permits exact retries after a lost response. A replacement
pod fences the previous pod UID; its fresh generation can resume the same
incomplete intent. A pending intent blocks unrelated changes. Released or
cancelled identities have tombstones until parent deletion. There are at most
seven children per parent, including draining and incomplete children, matching
the runtime's eight-placement bound. Pool slot limits apply independently.

CSI serializes these operations with normal lifecycle calls under the existing
pool/volume locks. Parent re-publication restores child mounts; parent node
cleanup closes children first. PVC deletion removes detached children without
requiring a live allocator, including non-empty children, but refuses active or
ambiguous mappings. It removes only empty host mountpoint directories, never
recursively deleting uncertain mount trees. The staging fixture qualifies kubelet
propagation and pod/CSI restart; node reboot and production readiness remain
separate gates. Hosted throughput measurements are recorded in validation.md.
The separate 128-device qualification covers bounded scattered writes and cold
activation and now meets the five-second observation budget. It is not
worst-case metadata mapping qualification.

### Isolating small-write latency

`latency_stack.rb` is a disposable-Linux-VM diagnostic, not a hosted-node setup
script. Dispatch `kura-volumes-csi-image.yml` with only `latency_only=true` to
compare the same pinned experimental runtime on ten configurations in forward
and reverse order. It creates its own loop-backed VG, holds virtual size and
runtime limits constant, and varies thin mapping, project quotas, dm-crypt write
submission, and XFS format settings. The format factor groups `reflink=0` and a
64 MiB log; a result for that factor requires further isolation before choosing
either setting. Identical mkfs arguments can still infer different allocation
group counts and log stripes from device hints; separate controls override the
log stripe alone and the full data geometry, recording actual `xfs_info` output.
It does not publish images or change any cluster.

`thin_quota` retains the original inferred log stripe as the regression control;
`thin_log4k` represents the corrected fresh-volume format. The job also runs the
real CSI lifecycle qualification on 64 KiB and 512 KiB pools and checks the
resulting filesystem's log geometry. Existing filesystems are not reformatted.

Each configuration records the original 400-request cold PUT/GET phase, then a
separate 400-write warmup and 4,000-request PUT/GET phase, with cgroup counters
around both. Serial 16 KiB writes compare fresh allocation, overwrite, and
buffered writes, recording write and fdatasync latency separately. These probes
help distinguish allocation/durability costs from request scheduling; their
absolute latency is not a prediction for hosted hardware. No durability barrier,
quota, reserve, or production setting is disabled as an optimization by this
experiment. Cleanup refuses to delete backing if unmount or mapper close fails.
