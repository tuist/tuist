# Encryption and subsequent disk sharing

Reviewed on 2026-10-28 against encryption PR #14152 at
`33ad1b6c2cfbbdd572d713c008b9b2a3951a8f4d` and sharing PR #14825 at
`34956ca681a3dc0dc257ee5b4d0d65814bd5f23d`.

**The current encrypted thin layout has not passed the compatibility gate.**
Encryption remains the deliverable of #14152. The sharing policy remains in
#14825; this review does not move that implementation into the encryption PR.
An API adapter alone cannot make the current layout deliver sharing's admission
benefit. Keep the encryption PR draft rather than promise that a later change
can safely remove full-ceiling reservations.

The subsequent [ext4/fscrypt experiment](../fscrypt/validation.md) demonstrates
physical grant transfer with the unchanged #14825 policy on a shared encrypted
filesystem. That bounded alternative passes its mechanism and policy checks,
but currently loses about 32% of cache churn throughput against shared XFS and
roughly doubles runtime CPU in the VM comparison. The thin LUKS control also
lost about 31% of throughput against XFS in those VMs; these are not matched
Paris staging results or proof of a production regression of that size.
It is not implemented in CSI
and does not change the conclusions about the existing thin layout below.
See its [integration gates](../fscrypt/integration.md) for key lifecycle,
confinement, admission and migration requirements before a replacement.

## What can be reused, and what must change

| Area | Current implementation | Consequence for the later sharing PR |
| --- | --- | --- |
| Key custody and transport | Versioned tenant shares, OpenBao provider, volume-bound derivation and sealed CSI delivery | Independent of allocation policy; no reason to replace this for sharing. Permanent hosted OpenBao custody is a separate uncompleted release gate. |
| Policy | `diskallocator.Targets` divides usable capacity by floor, demand and ceiling | Reusable policy, provided its input bytes have one defined meaning and every result is only a target. It cannot authorize physical allocations itself. |
| Runtime | Expiring pod-bound budget files drive write refusal and bounded segment retirement | Reusable behavior. Preserve pod UID fencing across replacements; do not substitute stable PV identity for the runtime incarnation. |
| Inventory | Sharing resolves hostPath/local PVs and rejects CSI PVs | Add a CSI inventory/backend path. Resolve the PVC UID and CSI volume ID, verify node ownership, and join it to CSI's LV/pool identities and pod UID. |
| Mutation ownership | Sharing runs `xfs_quota`; CSI owns its inner filesystem and lifecycle locks | The CSI backend must call the node-local API. It must not run a second quota writer or acquire the local-path lock as if that protected CSI operations. |
| Units | Sharing's `Current` is the whole filesystem quota. CSI's grant is useful cache bytes, with 2 GiB added for workspace | Define a versioned sizing conversion before connecting these APIs. Passing the same integer through both changes the promised capacity and can count workspace twice. |
| Accounting | Sharing charges `max(Used, Current)` on one shared XFS filesystem | This equation is not a thin-pool safety bound. Keep quota usage, mapped allocation, backing commitment, pool metadata and reserves separate. |
| Reclamation | CSI reports observed physical release, but always zero released commitment | TRIM can make blocks reusable by already-backed volumes. It cannot fund additional admission or aggregate ceilings exceeding the pool in the implemented mode. |
| Scheduling | Encryption reserves converted ceilings in `tuist.dev/kura-disk`; sharing uses floor-sized local-path claims and ephemeral-storage requests | A future CSI mode must change server admission, controller requests and node capacity consistently. A floor-sized PVC cannot also be interpreted by CSI as the virtual ceiling. |
| Retained storage | CSI keeps durable records and charges volumes until confirmed LV deletion | Preserve this inventory even when sharing's active-pod inventory no longer contains the volume. Pod disappearance must not release its commitment. |

The bounded integration changes are inventory, a CSI backend, explicit sizing
conversion and coordinated scheduling. The unresolved physical backing model
is larger than those changes. Consequently, this review does **not** establish
that #14825 can land after the current storage layout with only small changes.

## Why shrinking a quota is insufficient

The real-stack test demonstrates the distinction:

1. Delete an open file and trim: its mappings remain charged.
2. Close it and trim: per-volume and pool mapped bytes fall.
3. Write into another already-backed encrypted volume: it uses released blocks.
4. Reduce grants or restart CSI: full virtual-ceiling commitments remain.
5. Delete the original LV and its durable record: only then is its commitment
   released for new admission.

Passing steps 1–3 is physical recycling, not proof of overcommitted admission.
The independent negative test keeps a 256 MiB XFS project quota while small
writes and ignored discard consume over 512 MiB of additional thin mappings.
Restoring working discard still cannot release chunks containing live blocks.
Replacing quota usage with `max(mapped, quota)` does not fix future allocation:
already admitted writes may map more chunks than their filesystem byte count.

Full virtual backing is the implementation's containment mechanism. Removing
it without a new proven physical bound would expose every tenant in the pool
to exhaustion. Polling, runtime lease expiry, extra reserve percentages and
automatic extension are not independently sufficient proofs of that bound.

## Contract required before committing the final layout

The encryption work must establish these capabilities without implementing
fairness policy or pressure-driven migration:

- Stable volume identity plus separate pod incarnation/generation fencing.
- One CSI owner for creation, quota changes, reclaim and deletion, with durable
  admission transactions serialized against lifecycle operations.
- Explicit capacity mode and units. Consumers must reject an unsupported mode;
  `ceiling-backed-v1` must never be treated as shared-grant admission.
- Authoritative mapped data and pool metadata observations, all retained and
  incomplete allocations, reserves and conservative behavior for stale reads.
- A physically bounded writable grant whose backing can be transferred after
  eviction and verified reclaim without replacing the filesystem or volume.
- A demonstrated limit on in-flight growth during allocator outages, failed
  discard and data/metadata pressure, including fragmentation and open files.

The last two requirements are **not implemented**. There is no qualified
`shared-grants-v1` mode to adapt to today. A later adapter must not disguise that
absence by translating a successful quota read-back into released pool backing.

Acceptance needs an encrypted two-volume test where aggregate virtual ceilings
exceed usable physical capacity, floors and current grants remain backed, A's
eviction/reclaim funds B, and identities/filesystems survive repeated transfers.
Repeat with stale leases, restarts, failed discard, concurrent lifecycle calls,
retained volumes and both reserve limits. The current conservative test cannot
pass the aggregate-ceiling part by design. A new layout or enforcement mechanism
must pass it before we claim that encryption avoids a disruptive later migration.

## Exploration: retaining LUKS + XFS for capacity sharing

Design review on 2026-10-28 at encryption revision
`4428a0ee415743d7f44e40ad7c4b2a3db7ff4b67`, against the same sharing revision
above. **This section proposes work; it does not implement or qualify a new
capacity mode.** No new VM or staging experiment was run for this review.

### What the stock stack can enforce

The documented [dm-thin interface](https://docs.kernel.org/admin-guide/device-mapper/thin-provisioning.html)
exposes mapped sectors per device and pool-wide allocation controls, but no
per-device physical allocation limit. The
[Linux v6.17 implementation](https://github.com/torvalds/linux/blob/v6.17/drivers/md/dm-thin.c)
likewise has no limit-setting message for that purpose. Its pool message handler
supports create, snapshot, delete, transaction ID and metadata snapshot
operations. This review does not establish the capabilities of every future
kernel or vendor extension.

There are two different limits to distinguish: XFS can reject a file allocation
at its project quota, while dm-thin allocates whole chunks for block writes.
The existing negative test demonstrates why these are not interchangeable.
Reducing chunk size or aligning typical writes may improve average utilization;
neither bounds allocation after arbitrary churn and failed discard. A 512 KiB
chunk can be pinned by one 4 KiB live block. With discard ignored, even a limit
on currently live blocks cannot bound historical mappings short of device size.

Adding a hard mapped-block limit to dm-thin would require more than a counter:
atomic reservations before allocation, persistent recovery, in-flight accounting,
metadata bounds, and defined behavior when allocation is denied. A write denied
below XFS can be a filesystem I/O failure, including a journal failure, rather
than an ordinary project-quota error. This is a kernel/filesystem integration
project; it is not a small CSI adapter. Pool-wide queue/error-on-full behavior is
not a replacement: [LVM documents filesystem damage and recovery risks](https://man7.org/linux/man-pages/man7/lvmthin.7.html)
when a pool fills.

### Candidate to prototype: independently reclaimable encrypted volumes

Keep thin LVM, per-volume LUKS keys derived through the tenant/OpenBao key path,
and XFS, but make the allocation unit smaller than an instance's lifetime
ceiling. An instance has a stable base volume and separately created volumes
for borrowed capacity. Each borrowed volume stores a group of cache segments.
The base holds durable runtime state and a guaranteed cache floor; borrowed
volumes must contain only data eligible for the existing cache eviction rules.

Every created device remains fully backed. The logical instance ceiling can
exceed its current total device capacity because the additional devices do not
exist until granted. For illustration, a 32 GiB cache floor and 128 GiB ceiling
could receive two 16 GiB useful-cache units for a 64 GiB grant. Reclaiming one
unit lowers the grant to 48 GiB and makes its backing available elsewhere.
These numbers exclude overhead and are examples, not selected production sizes.

The data invariant becomes:

```
sum(round_up_pool_chunk(virtual_bytes) for every committed device or intent)
    + data_reserve <= pool_data_bytes
```

Commitments include base, borrowed, retained, creating and deleting devices.
The kernel device size bounds each device's addressable allocation even if
quota enforcement, runtime cooperation or discard fails. No snapshots,
external origins or unmanaged devices are allowed. Metadata needs its own
admission bound, device-count limit and transaction/recovery reserve; the
current metadata profile must be requalified for the greater device count and
create/delete rate. An exhausted metadata reserve must block new device
admission while preserving the provisioned budget for existing I/O and cleanup.

This preserves the conservative safety principle but reserves **current
allocated units rather than every possible future unit**. It does not enable
physical overcommit of existing devices. Empty space within an assigned unit
remains committed until that whole unit is returned.

CSI would own the following durable transaction, under the same pool/lifecycle
locks used for other operations:

1. Record a lower target and mark selected borrowed units as draining. Stop
   placing new segments there; retain their full charge and old effective grant.
2. Retire their cache segments under the existing eviction/durability rules.
   Drain readers, mappings and open descriptors. If a reader remains or eviction
   is ineligible, delay the transfer; do not revoke a live read or lose a write
   acknowledged under stronger retention guarantees.
3. Remove publication in every relevant mount namespace, unmount normally,
   close the encryption mapping and delete the LV using existing safeguards.
   A runtime acknowledgment alone is insufficient. Lazy/forced unmount is not
   proof of release. Optional TRIM may reduce mappings early but releases no
   commitment while the unit remains writable.
4. Verify the device and its thin mappings are gone and reconcile pool counters
   and durable state. Concurrent writes to other fully backed devices can mask
   the pool's net decrease; use per-device deletion evidence plus pool consistency,
   not an expected aggregate delta alone. Unknown state stays charged.
5. Commit the released reservation. Only then reserve and create a new unit for
   the recipient, with a new identity/key, quotas and publication verified before
   increasing its effective runtime grant.

An allocator crash or stale lease therefore delays growth/reclamation rather
than allowing an unbacked write. A restart reconstructs all pending charges
before permitting new allocations. Never mount the donor's filesystem under the
recipient or reuse its cryptographic identity. Failures after deletion but before
ledger commit leak available capacity temporarily; recovery may release it only
after confirming deletion. Retry deduplication and pod-incarnation fencing are
required at each publication boundary.

This path avoids shrinking XFS or backfilling a replacement for the entire
instance. It still pays for retiring one unit's cached contents, LUKS formatting,
XFS creation and mount operations. Small units reduce stranded capacity and
eviction granularity but increase filesystem, journal, device and key overhead.
Benchmark several sizes before choosing one; do not blindly repeat the current
2 GiB workspace allowance for every unit. Workspace, LUKS headers, XFS metadata,
logs, inode limits and rotation headroom need a new explicit sizing profile.

### Bounded prototype result — 2026-10-28

The [real CSI/Kura prototype](borrowed/README.md) now demonstrates the allocation
transfer in an isolated Linux VM. [Qualification and raw-evidence links](borrowed/validation.md)
record 53 passing assertions, retained charges across failed discard/open readers
and CSI reconstruction, exactly one winner for competing creates, and unchanged
base identities. The unchanged #14825 `Targets` function selected 8/4 then
4/8 GiB; its production agent/backend was not integrated.

The comparison completed 18,240 HTTP requests without reported failures, but
borrowed-volume upload churn was 73.91–74.88 MiB/s versus 79.99–80.24 for one
thin LUKS/XFS volume and 96.89–98.87 for shared XFS. This supports feasibility,
not performance acceptance or a production layout decision. Publication used
Docker mount propagation and fixture keys; real Kubernetes child authorization,
OpenBao, reboot/fencing and metadata-scale qualification remain outstanding.
The later production acceptance list below is not wholly covered by this test.

Whole-unit backing/deletion also works with thick LUKS/XFS devices. Thin storage
is not required for the demonstrated granularity of sharing; compare thick units
before committing to the backend. The shipping CSI contract remains unchanged.

### Compatibility costs that must be accepted explicitly

This is a change to the original single-large-filesystem requirement: the
**logical instance** remains stable, but borrowed filesystems are disposable.
It cannot be presented as enabling arbitrary quota reductions on the existing
single ceiling-sized filesystem. Current XFS documentation describes only
[limited last-allocation-group shrink support](https://man7.org/linux/man-pages/man8/xfs_growfs.8.html);
that is not a qualified arbitrary shrink-and-transfer path for this stack.

| Area | Required change |
| --- | --- |
| #14825 fairness | `Targets` can continue computing floor/demand/ceiling targets. Add explicit unit rounding, overhead conversion and feedback of effective grants; fairness operates on targets, not spendable capacity. |
| #14825 reconciliation | `Backend.SetLimit` and the agent's immediate accounting assume quota mutations. Use an asynchronous CSI operation and charge its actual committed result; a queued unit deletion must not look like a completed shrink. This is more than substituting `xfs_quota` with HTTP. |
| Kura runtime | `utils::segment_path` currently resolves one `data_dir/segments`, and `Store` recovery scans that directory. Add durable segment-to-unit ownership, multi-root recovery, placement and targeted drain. Reader-held `Arc<PersistentFile>` handles must be drained. Audit rename paths: cross-filesystem atomic rename cannot be assumed. |
| CSI identity and keys | Retain stable parent PVC/CSI identity; introduce immutable child identities and durable parent ownership. Extend key-service authorization/derivation to validated children. The existing PV-name-only key request cannot simply accept arbitrary child IDs. |
| Publication | Qualify dynamic child mounts in the pod namespace and after restage. A host submount does not automatically become visible in an existing pod. Do not grant tenant mount privileges; a CSI-managed parent/submount contract needs a real Kubernetes test. |
| Scheduling | Reserve converted floors and all outstanding physical commitments consistently. CSI remains the final admission authority. Borrowed grants cannot consume backing promised to newly admitted floors; reconciliation must handle retained allocations absent from active pod inventory. |
| Existing volumes | A large monolithic volume cannot silently become a small base plus units. Keeping it as a base strands its original full reservation. Releasing that reservation needs a one-time staged migration or a qualified in-place segmentation strategy; do not promise zero later migration. |

OpenBao custody, tenant ownership, encryption transport and migration safeguards
remain applicable. The policy can be reused, but runtime and CSI changes are
substantial enough that this review does **not** clear the “only small changes
after encryption” compatibility gate.

### Alternatives and recommended next gate

| Direction | Assessment |
| --- | --- |
| One huge thin LV plus project quota/TRIM/polling | Fails the existing physical-allocation counterexample; reject for overcommit. |
| New per-device dm-thin physical quota | Preserves one filesystem, but requires kernel development and safe XFS allocation-failure behavior. Do not make it the default implementation plan. |
| Per-tenant thin pools | Contains allocation within each pool, but transferring backing out of a populated pool is a separate shrink/relocation problem; growing pools alone does not provide repeated redistribution. |
| Sparse loop files on shared XFS with outer quotas | Can bound outer allocation, but introduces nested filesystem I/O and quota failures below inner XFS. Earlier loop measurements were slower; needs independent correctness and performance qualification. |
| Fully backed base plus borrowed encrypted volumes | Most concrete stock-stack path to prototype. Trades fine-grained sharing for explicit units and runtime/lifecycle work. Existing thin performance is encouraging, not proof of this multi-volume layout's performance. |

Recommend a bounded feasibility prototype of the last option before changing
the shipping storage contract. It must exercise the real Kura runtime and CSI,
not only demonstrate `lvcreate`/`lvremove`:

- Two instances whose logical ceilings exceed usable pool capacity. Both retain
  their guaranteed floors; A returns a borrowed unit and B consumes the released
  commitment, without replacing either base filesystem or requiring equivalent
  temporary space for copying the donor's retained cache.
- Reads held open during drain, failed discard, runtime/CSI/node restarts at
  transaction boundaries, concurrent create/delete/grant operations, stale pod
  incarnations, retained units and ambiguous cleanup. Every unsafe/unknown case
  must delay credit; no pool-wide failure may be used as ordinary enforcement.
- Maximum device-count and adversarial fragmentation/churn tests for data and
  metadata backing, with the allocator stopped and writes continuing. Qualify
  reserve refusal separately from recovery after injected exhaustion.
- Real Kubernetes publication and key authorization for child devices, plus
  staged catch-up, destination-bound acknowledgments and endpoint handoff.
- Matched shared-XFS, current single-volume thin LUKS and multi-volume thin LUKS
  benchmarks: small/large reads and writes, churn, grant-transfer latency, cache
  hit-rate effects and whole-node CPU/memory. Alternate run order on the same
  staging hardware/image/resource limits; retain cold/pressure measurements.

If the single-filesystem requirement is retained, this proposal is unsuitable.
The honest options then remain conservative ceiling backing or a separately
qualified physical-allocation enforcement implementation. There is no demonstrated
configuration switch that provides both the current layout and safe shared grants.

## Performance and rollout boundary

See [validation.md](validation.md) for separate hosted application, hosted direct
I/O and disposable-VM results. The fresh VM run is a mechanism regression check;
it cannot replace hosted NVMe measurements or OpenBao deployment validation.
The prior encrypted staging candidate still has a random-read regression and
about 6 ms higher small-PUT p95 against the shared-XFS baseline. No later
plaintext sharing benchmark supersedes those measurements.

No storage, scheduling or enrollment settings were changed for this review.
Preserve the source-node migration gate, replica catch-up, destination-bound
write acknowledgments, endpoint handoff and retained-volume deletion checks.
Existing thick storage still needs landing capacity and safe migration; it
cannot be converted into a shared thin pool in place. Qualify the final layout
and OpenBao path on staging, then rehearse the Tuist-first cohort before any
production enrollment.
