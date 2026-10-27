# Thin encrypted Kura volumes

Status: conservative thin CSI implementation, 2026-10-27. The implemented
`ceiling-backed-v1` API and rollout contract are in [interface.md](interface.md).
This document also records requirements for a future shared admission mode;
`shared-grants-v1` is **not implemented or qualified**. PR #14152 remains draft
while qualification and staging evidence are collected. Local evidence and
outstanding acceptance gates are in [validation.md](validation.md).

Related work: [LVM and encryption #14152](https://github.com/tuist/tuist/pull/14152)
and [disk sharing #14825](https://github.com/tuist/tuist/pull/14825). The latter
currently operates on shared XFS. It must consume this storage interface after
#14152 lands instead of independently administering the encrypted filesystems.
Full fairness policy and pressure-driven pod migration belong outside this PR.

## Decision and release boundary

Use a shared per-node LVM thin pool, one thin LV and LUKS2 mapping per CSI volume,
and XFS within each mapping. Keep the existing versioned per-account keys and
per-volume derivation. Filesystem virtual size covers the instance's configured
ceiling and overhead. Routine grant reductions change a project quota, not the
filesystem size. No filesystem shrinking or volume replacement on that path.

Physical-exhaustion protection is a blocking acceptance criterion. Merely
adding `-V` to lvcreate and enabling discard is not sufficient. Implement and
qualify the storage interface before merging this replacement design; enable
physical overcommit only after the additional shared-mode gate passes.

The implemented conservative mode and blocked future mode have different promises:

| Mode | Physical commitment | Scheduler reservation | Can aggregate virtual ceilings exceed pool capacity? |
| --- | --- | --- | --- |
| `ceiling-backed-v1` | Every complete virtual block device plus pool reserves | Converted ceiling, including per-volume overhead | No |
| `shared-grants-v1` | Floors, outstanding enforceable grants, unreclaimed allocations and reserves | Converted floor, with a node-local grant/admission transaction as a second gate | Yes, only after pressure containment is qualified |

The conservative first mode is useful for qualifying thin layout, encryption,
quota operations and reclamation without data oversubscription. It does **not**
realize the projected regional admission gains. Do not advertise floor-sized
Kubernetes requests in that mode. If shared-mode qualification fails, retain
ceiling backing rather than enabling optimistic accounting.

## Layout and sizing

The `data` LV remains a separate thick XFS filesystem for host state. The thin
pool has separately sized data and metadata LVs, a metadata spare for repair,
and unallocated VG recovery headroom. A metadata spare is not active metadata
capacity. Pool sizing must leave explicit reserves; do not allocate 100%FREE.
Use 512 KiB chunks for fresh pools, retaining qualification for existing 64 KiB
pools. Changing chunk size requires a new pool. Larger chunks can retain more
physical allocation around small live filesystem extents; this is another reason
quota/free-space observations cannot substitute for physical mapped counters.
Prohibit snapshots, external origins, deduplication, unmanaged thin LVs and raw
block publication in the qualified pool. They change allocation/accounting
assumptions and require a new qualification profile.

Use a new immutable layout identifier, `thin-luks-xfs-v1`, rather than calling
both thick and thin volumes `backing: lvm`. Add a separately named StorageClass
(e.g. `kura-thin-encrypted-nvme`); do not mutate existing class parameters or
reinterpret existing PV attributes. PV context carries the layout, CSI volume
ID, LV UUID, pool UUID and sizing-policy version. Existing `lvm`/`file` values
continue to mean their actual historical backing.

Each quantity is an integer number of bytes, rounded conservatively:

- `floor_cache_bytes`: guaranteed useful cache capacity, protected by admission.
- `grant_cache_bytes`: current useful capacity allowed by policy, bounded by
  floor and ceiling while active. A lower shrink *target* is not a new grant.
- `ceiling_cache_bytes`: maximum useful capacity the instance may be granted.
- `quota_hard_bytes`: kernel limit for all project-accounted files. It includes
  cache bytes, staged uploads, rotation/backfill workspace, RocksDB and other
  runtime files; it is not identical to useful cache bytes.
- `virtual_bytes`: complete LV size, including the LUKS offset, filesystem
  journal, allocation-group metadata and space needed to fit the ceiling quota.
- `mapped_bytes`: current physical thin mapping allocation, including filesystem
  and encryption overhead and deleted but unreclaimed extents.

Define a versioned sizing function shared by server admission, controller and
CSI; return its component breakdown through the interface:

```
quota(G) = round_up(G + runtime_workspace(G, profile), quota_unit)
virtual(C) = round_up(luks_offset + quota(C) + xfs_overhead(C, profile), chunk)
floor_commitment = physical_bound(quota(F), profile) + volume_overhead
```

The existing 2 GiB staged-request allowance must be included, along with
retirement/backfill and metadata workspace; do not deduct it silently from the
advertised cache floor. Bound the XFS journal explicitly rather than allowing
its default to grow with an overcommitted virtual size. Calibrate metadata and
fragmentation allowances with the final Kura file layout; a guessed percentage
is not an established physical bound. Reject unknown sizing profiles and
integer overflow. Increasing a ceiling beyond the formatted size requires an
explicit, separately tested expansion or the existing safe replacement path.
Do not advertise CSI expansion support until that operation exists.

## Project quota enforcement

Mount XFS with `prjquota,nodev,nosuid,noatime`; verify both project accounting
and enforcement, not just the mount flag. Assign nonzero project ID 1 to the
filesystem root and inheritance to all directories before publishing it. IDs
may repeat because each tenant has a separate filesystem. Include every
writable runtime directory, not just the segment directory. Check existing
inodes during adoption and check the root's ID/inheritance on every restage.
No runtime writable alias may escape this project tree.

CSI sets the project hard block limit and reads it back using the kernel quota
interface. Match the soft limit to the hard limit; grace periods are not a
capacity mechanism. Round promises down and reservations up. Limit zero means
unlimited in XFS: never use it as a write fence. Bound inode consumption too;
large counts of tiny files can exhaust metadata independently of byte usage.
Kura pods must lack capabilities that can change quotas/project IDs, remount
filesystems or access underlying devices. A host administrator remains trusted.

XFS can reject allocations slightly below the nominal limit because it reserves
transaction workspace. Report quota enforcement separately from pool pressure (project quotas can also return ENOSPC), and keep
workspace in the sizing model. Open deleted files remain charged until their
last reference is gone. Runtime eviction and expiring leases improve behavior
and stop new commits; they do not replace kernel enforcement.

**A project quota does not bound mapped thin allocation.** Failed/ignored
discard permits quota reuse while old mappings remain. Small writes also consume
whole thin chunks. Therefore neither `sum(quota limits) <= pool size` nor
`sum(max(mapped, quota)) <= pool size` proves future writes remain safe. This
negative property is an acceptance test, not an implementation detail to hide.

## CSI and allocator interface

CSI is the only writer of LVM, dm-crypt and XFS state. The allocator has read-only
Kubernetes discovery and access to a dedicated node-local Unix socket; it needs
no host devices, mount namespace, quota commands or key-service identity. The
socket is not mounted in Kura pods. Authorize its peer UID/group and restrict it
to the intended allocator workload. Protect against replacement by another host
process under the same trust assumptions as other privileged node components.

Version the protocol independently from CSI. Proposed operations:

| Operation | Request | Result and required semantics |
| --- | --- | --- |
| `ObserveNode` | API version | Fresh bounded-duration inventory, node/boot ID, ledger epoch, snapshot sequence, pool data/metadata counters and health, reserves, every volume and pending operation; explicit stale/unknown flags |
| `SetGrant` | Stable volume ID + LV UUID, pod UID, expected generation/epoch, operation UUID, desired grant | CAS under pool lock; validate live publication, physical commitments and quota read-back; return effective quota, grant and next generation only after durable commit |
| `Reclaim` | Same identity/fencing fields, shrink target and operation UUID | Trigger bounded sync/trim, return operation state and before/after physical observations; never return a reusable credit inferred from fstrim's reported bytes |
| `GetOperation` | Operation UUID | Durable pending/completed/failed status and current generation, allowing retry after a lost response |

No arbitrary device names, mount paths, shell fragments, quota project IDs or
key material are accepted from the allocator. CSI resolves all paths from its
own validated volume record. `ObserveNode` must include retained, unstaged,
terminating, partially created and deleting volumes, not only mounted pods.
Accounting failure for any pool member blocks growth for the whole pool.

Stable identity is `(CSI volume ID, LV UUID, pool UUID)`. It survives pod and
CSI-process replacements. Runtime lease identity additionally includes pod UID,
volume ID, ledger epoch and monotonic grant generation. Enable and verify CSI
`podInfoOnMount` before relying on kubelet's pod UID; currently it is false.
Validate the bound PVC UID and live pod-to-PVC association. An allocator request
cannot bind a new pod or renew an old pod's lease. CSI records the binding during
NodePublish and invalidates that incarnation during unpublish/replacement.
Republishing the same volume does not erase its physical charge or change keys.

Use one durable node ledger and a fixed lock order: pool lock, then volume lock.
Create, stage, publish, grant, reclaim, unstage and delete participate. Retain
per-volume flock across process restarts, as the current driver does. Operations
must not deadlock by taking locks in the reverse order; keep long trim work
bounded and represent pending work durably. The allocator never takes these
locks itself. Multiple CSI pods sharing a state directory must not create a
second independent pool writer.

An increase reserves capacity and fsyncs intent **before** increasing the quota.
A crash can leak a reservation but cannot expose an unrecorded allowance. Read
back quota before committing the new grant or issuing a lease. On restart,
reconcile journal, actual LV inventory and kernel quota state; take the larger
commitment and block growth on disagreement. Replay operation UUIDs idempotently.
Never make incomplete cleanup or an expired lease a reason to forget a charge.

## Reclamation and physical accounting

Configure LUKS opens with `--allow-discards`. Configure dm-thin to process
discards; `nopassdown` can release pool mappings without requiring physical
NVMe TRIM. `ignore` is unqualified. Use explicit bounded fstrim for reclamation;
continuous mount-time discard may be evaluated separately for cost and latency.
Discards reveal allocation/freeing patterns and potentially filesystem usage to
an observer of the underlying storage. They do not disclose plaintext, but they
weaken allocation-pattern privacy. Document this deliberate encryption tradeoff.

The shrink transaction is:

1. Publish a lower runtime target while retaining the old grant and commitment.
2. Runtime evicts under its existing reader, writer and handover safeguards.
3. CSI lowers and reads back the hard quota. Writes beyond it fail even if old
   occupancy is still above the target. Keep the old physical commitment while
   open files, incomplete eviction or other unreclaimed blocks remain.
4. Sync and issue discard through the encrypted mapping. Command success does
   not complete the transaction. Record timeout/failure as pending, with no
   reusable credit.
5. Re-read volume mappings and pool data/metadata state. Account for unrelated
   concurrent runtime writes; a pool delta alone cannot attribute reclamation to
   one volume. Require the donor's physical charge and aggregate outstanding
   commitments to fit the proposed new state. Repeat observations as needed.
6. Commit the lower reservation durably. Only a later serialized grant
   transaction can allocate the resulting available capacity elsewhere.

Use integer kernel dm-thin mapped sectors for active volume allocation, and
integer pool used/total data and metadata block counters. Percentages from `lvs`
are useful diagnostics, not authoritative byte accounting. For inactive/retained
thin IDs, use a committed, held metadata snapshot and the matching metadata
inspection tools, or conservatively retain the last/worst commitment until
verified. Do not activate a key mapping solely to obtain allocation statistics.
Include pool transaction identity, observation start/end times and chunk size.

Inventory the entire pool. Refuse growth if a thin ID has no recognized owner,
if snapshots/shared blocks appear, or if the inventory cannot be reconciled.
Pool-used bytes can exceed recognized per-volume sums: classify the residual as
charged unknown usage, never free space. DeleteVolume keeps its charge through
unmount/close, header erasure, LV removal and verified mapping release. Never
remove the durable identity first. Preserve existing refusal to delete an active
mapping and existing safe key-version behavior.

`tuist.dev/kura-disk` remains a scheduling reservation, not instantaneous free
space. Advertise total reservable capacity after fixed pool reserves, in the
same units as requests. Kubernetes subtracts pod requests; do not subtract live
pod floors again from the published total. Server admission additionally charges
retained/unmatched resources. In shared mode, a new floor must also be funded by
the node-local ledger before volume creation or publication. Scheduling a pod
cannot by itself reclaim somebody else's busy grant. Refuse/defer the new floor
until its capacity is actually available; fail or reschedule rather than write
into an unfunded promise.

## Exhaustion gate and failure behavior

Data and metadata need separate safety budgets and health decisions. Reserve
metadata for the worst qualified mapping count, thin-device count, transaction
updates and repair; metadata exhaustion cannot be recovered by hoping that a
data trim frees it. Validate the maximum pool size/chunk size/volume-count
profile using `thin_metadata_size` plus conservative tested headroom. Reject
creation outside that profile. Keep the metadata spare and VG headroom separate
from usable tenant capacity. `error_if_no_space` is a final damage limiter, not
pre-exhaustion protection: ENOSPC/EIO from a full thin pool can shut down XFS.

The shared-mode gate must demonstrate a bound covering allocations after the
last trustworthy observation, outstanding/dirty I/O, thin-chunk amplification,
XFS metadata, failed discard and the time needed to stop allocation. Specify the
actual kernel enforcement/fencing mechanism and verify it under CSI/allocator
crash and process pause. Lowering a project quota does not stop writes into
already allocated filesystem blocks, which may still map new thin chunks.
Remount/freeze requests can themselves wait on I/O. Do not assume either is a
bounded, always available emergency brake.

If that bound and fail-closed behavior cannot be established, keep
`ceiling-backed-v1`: the sum of complete virtual devices fits the pool after
reserves regardless of quota reuse or discard failure. No dynamic conversion
from an overcommitted node to this mode; first reclaim/move until complete
ceilings fit. This is the selected fallback, not permission to weaken the gate.

| Failure | Required response |
| --- | --- |
| Stale/incomplete counters, unknown thin ID or quota mismatch | No growth/new floors; do not renew a larger lease; retain conservative charges and alert |
| Allocator outage | Existing kernel quotas remain; runtime leases expire and refuse new commits; charges persist. In shared mode, independently qualified containment must still work |
| CSI outage/restart | No allocation mutations until reconciliation; durable quotas/reservations survive; shared-mode containment must not depend solely on that process |
| Delayed/failed/ignored discard | Keep shrink pending and old commitment; no reassignment on deletion or fstrim success alone |
| Data or metadata reserve threshold | Reject create/increase, stop new writes via qualified fencing before exhaustion; retain reads/cleanup only where safe |
| Pool read-only, needs-check, error or actual exhaustion | Fail closed; stop publication/writes, alert, preserve metadata for repair. Do not silently recreate volumes |
| VG free space exhausted | No reliance on autoextension; operate within pre-backed limits or refuse work |

No production flag should enable shared mode until the implementation and
qualification evidence exist. The first implementation must reject an unsupported
shared-mode configuration, rather than silently degrading to weaker accounting.

## Migration and rollback

Keep regional enrollment explicit and preserve the source-node annotation gate,
one selected cordoned node at a time. Never infer permission to reformat a joined
host from a change in driver defaults. An existing populated VG is not an empty
thin pool. Do not use `lvconvert --thinpool` on a data-bearing thick tenant LV;
that is not a fleet migration. External-origin conversion retains the old thick
allocation and is not a substitute for reclaimable shared capacity.

Prepare a new/rebuilt node with reviewed pool geometry and enough landing
capacity. Thick and thin nodes coexist with explicit layout attributes. Update
controller class recognition, disk reservations, capacity checks and backing
comparison together; current `backing: lvm` shortcut must not bypass the
source-node migration gate for a thick-to-thin transition. Stage the new driver
before requesting new layout claims.

For each selected source, check disk/CPU/memory/taints/placement and retained
volumes, create the replacement, wait for replica catch-up, perform endpoint
handoff, then remove the old claim through existing deletion safeguards. Keep
single-copy standby creation, OnDelete/partition pauses, fencing and shared
StatefulSet-template holds. Cross-host legacy layouts still need their explicit
placement/recovery plan. Thin provisioning does not relax any of these gates.

A node with sufficient genuinely free VG extents can host a separate new pool
alongside old thick LVs, but both pools' commitments and the old thick extents
remain charged. A busy node without that room needs evacuation/reinstall or
external landing capacity. Do not promise zero migration spare capacity or a
whole-fleet doubling requirement: move one source at a time and recycle it.

Rollback stops new enrollment and growth. Keep the thin-capable CSI, key service,
quotas and ledger for existing volumes. Reverting to a thick-only driver cannot
mount/manage these interfaces safely. To remove sharing, first fund all complete
ceilings, reclaim or migrate as required, then change admission. Restore a thick
layout through replica replacement, never in-place XFS shrinking.

## Required evidence before implementation rollout

The local stack harness proves individual mechanisms and negative cases. It is
not a substitute for exercising the final CSI code. Required gates include:

- Final CSI create/stage/publish/grant/reclaim/unpublish/delete with real encrypted
  volumes; concurrent RPCs, cancellations and crashes at every durable boundary.
- Reclaim from A to B with physical verification, open deleted files, delayed and
  failed/ignored discard, cold reactivation, changed pod UID and replayed leases.
- Data and metadata pressure independently, stale observations, loss/pause of
  either process, restart reconciliation, unknown/retained/deleting volumes,
  exhaustion without VG extension, write rejection before reserves are spent.
- Cache HTTP reads/writes/eviction churn against thick LUKS/XFS on the same host,
  with CPU, memory, throughput and tail latency. Separate local-VM mechanism
  benchmarks from representative hosted NVMe results.
- Staged migration on staging using the new layout, including thick-to-thin,
  replica catch-up, endpoint handoff and old allocation release. Existing
  thick-volume/OpenBao rehearsals remain historical evidence only.

Recalculate #14825's regional capacity gains using final pool geometry, floor
conversion, workspace/metadata reserves, retained charges and placement. Rerun
its memory measurements with the final CSI service, accounting inventory,
allocator and runtime. Neither the existing shared-XFS projections nor the
thick-LVM performance measurements are established results for this design.

## References

- [Kernel dm-thin status, discard and failure semantics](https://docs.kernel.org/admin-guide/device-mapper/thin-provisioning.html)
- [LVM thin-pool management and metadata](https://www.man7.org/linux/man-pages/man7/lvmthin.7.html)
- [XFS project quotas, inheritance and enforcement](https://www.man7.org/linux/man-pages/man8/xfs_quota.8.html)
- [Cryptsetup discard privacy tradeoff](https://man7.org/linux/man-pages/man8/cryptsetup-open.8.html)
