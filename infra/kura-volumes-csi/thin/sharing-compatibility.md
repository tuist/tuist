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
