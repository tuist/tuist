# Shared disk capacity for Kura

The implementation is opt-in and disabled in every region. It separates a
replica's protected floor, account ceiling and current kernel-enforced budget.
There is no lending or debt ledger. The separate admission-buffer change is
[PR #14809](https://github.com/tuist/tuist/pull/14809).

## Why

Disk admission previously reserved every claim in full, even when its cache
occupied much less. Free filesystem space could therefore coexist with refused
enterprise admission. Reducing the admission buffer releases a fixed margin;
sharing unused capacity above floors addresses the underlying reservation gap.
Disk differs from bandwidth: stored bytes persist, so a lower target cannot fund
another replica until its blocks and enforceable allowance have been released.

## Policy and accounting

| Quantity | Meaning | Can the sum exceed usable physical capacity? |
| --- | --- | --- |
| Floor | Protected capacity per physical replica | No |
| Ceiling | Account entitlement per replica | Yes |
| Current budget | Kernel project quota | No |
| Target | Desired allocation after reclamation | Never permission to spend a pending shrink |
| Actual use | Kernel allocated blocks, including unlinked open files | Charged at least in full |

The server retains the existing claim as the ceiling. An explicitly enabled
region reserves the plan's starting claim as its floor: 8 GiB for Air/Pro and
16 GiB for Enterprise, multiplied by replica count. Unknown account policy
falls back to full-claim accounting. The controller requests the floor in both
the PVC and pod's ephemeral-storage request. It sets no ephemeral-storage limit:
that limit does not enforce the local persistent volume's allocation.

`cmd/disk-agent` owns one XFS filesystem under an exclusive allocator lock. It
also shares `/var/lock/tuist-kura-quota.lock` with the local-path provisioner.
Its Kubernetes inventory resolves pod UID → PVC UID → local PV path using
three list requests, cached for at most five seconds between successful reads. Paths must
be on the configured filesystem, without symlinks, with unique inherited XFS
project IDs and finite enforced quotas. Missing or inconsistent observations
stop authorization renewal. No namespace or Kubernetes mutation is required.

The hosted provisioner records PV paths under `/opt/local-path-provisioner`,
a bind mount of `/data/local-path-provisioner`. The agent mounts that root
read-only and explicitly allows it with `--volume-root`; quota operations still
target `/data`. Every volume must be a nonsymlink descendant of an allowed root
on the same device as `/data`, with its own inherited project ID. Merely sharing
a path prefix or declaring an alternate root never permits another filesystem.

Usable capacity is managed project use plus filesystem available bytes, minus
unused commitments of every unmanaged project and a mandatory operational
reserve. An optional absolute cap can reduce this further. Retained and legacy
projects remain charged even when absent from the pod inventory. An unbounded
nonzero unmanaged project refuses allocation unless both block and inode reports
positively show it is fully released. XFS retains empty quota records after
the provisioner deletes a volume; an empty directory or open deleted inode still
has ownership and must not use that exception. Project zero's actual use is
already reflected in filesystem availability; future non-tenant growth must fit
inside the configured operational reserve.

The allocator reserves all floors, including idle ones, then divides surplus
equally among replicas with demand, capped by ceilings. Demand preserves occupied
blocks plus the runtime metadata allowance, bounded staging and 2 GiB of
rotation headroom; at 70% occupancy it also asks for
25% growth (at least 1 GiB). The largest recent demand is held for five minutes.
Targets use MiB granularity to avoid XFS rounding sub-block quota limits upward.

The kernel quota is the durable allocation record. There is no second journal
to reconcile after a crash. Shrink proceeds in this order:

1. Publish a lower runtime target while charging the old quota.
2. Let the runtime reclaim using its existing segment retirement protocol.
3. Observe actual allocated blocks at or below the target, lower the XFS quota,
   and reread kernel state.
4. Only then assign newly uncommitted capacity elsewhere.

Every observation charges `max(actual use, current quota)`. A restart rereads
quotas before granting anything. Open deleted files continue consuming quota.
Unexpected external growth freezes increases and writes while requesting
reclamation toward floors. A floor is a reservation, not a guarantee against
unbounded non-tenant writes or an incorrectly configured eviction reserve.

## Runtime protocol

The controller passes `KURA_DISK_BUDGET_FILE` and `KURA_DISK_VOLUME_ID` together,
requires an explicit `KURA_CAS_CAPACITY_BYTES` ceiling, mounts the node-owned
budget directory read-only, and gates startup on initial authorization. The
volume identity is the pod UID, so a replacement pod cannot adopt another pod's
file. Files contain version, identity, generation, expiry, floor, ceiling,
current quota, target and write permission. Updates use atomic rename.

The runtime checks identity, monotonic generations, bounds and both wall-clock
and monotonic expiry. The lease lasts 15 seconds. On expiry it refuses new
storage commits and continues reads and bounded cleanup; already admitted I/O
remains bounded by the kernel quota. It retains the last reclamation target.
A ceiling reduction may temporarily leave the old current quota above the new
ceiling while the target stays within it and physical reclamation completes.

The supervised worker polls once per second and retires one sealed segment per
pass. It preserves active writers, pinned readers, pending commits, the minimum
five-segment ring and handover holds. Ring sizing leaves bounded staging, one
segment rotation and metadata allowance inside the current target. It never
truncates files or deletes them outside ordinary retirement. If the nominal
ring fits but XFS still retains too many allocated blocks, quota-visible free
space drives further reclaim, stopping on no progress and preserving the floor. Configured ceiling
telemetry remains unchanged; allocation-induced evictions use `disk_pressure`
so contention cannot manufacture evidence for repeated entitlement growth.

## Behavior examples

With a 12 GiB usable node budget and two replicas with 4 GiB floors and 8 GiB
ceilings, A can use an 8 GiB quota while B is idle at 4 GiB. When both need more,
targets become 6 GiB each. A's quota remains charged at 8 GiB until its actual
blocks fall below 6 GiB. B waits at 4 GiB during pinned reclamation, then grows
to 6 GiB. Floors are never lent away.

For a frequent-eviction account, a larger ceiling changes entitlement without
reserving the entire ceiling. If its current node has surplus, its current
budget grows. If the node is contended, it receives its fair share after local
reclaim. Raising the ceiling cannot force another replica below its floor.
New or increased floors still pass region and per-node placement checks.

Another node's free capacity does not enlarge this node's budget. This change
does not introduce automatic pressure-driven movement or cross-region placement.
Existing controlled evacuation remains available. A future movement policy must
reserve the full destination budget and transfer overhead while retaining source
charges until cleanup, obey placement/residency policy, and preserve handover
barriers. It cannot be emergency protection: copying and DNS drain are slow.
If no eligible destination exists, local eviction and bounded writes keep the
instance within its budget. Adding a node supplies additional physical capacity.

## Enabling and rollback

No managed values or region enables sharing in this change. Build the matching
runtime/controller and `Dockerfile.disk-agent` image. The controller image
workflow publishes `ghcr.io/tuist/kura-disk-agent:sha-<12-character-sha>` alongside
the controller. Pin that image in `kuraController.sharedDisk.image`.

On a qualified Linux node, verify `/data` is XFS with project accounting and
enforcement enabled, and that the local-path provisioner uses the shared lock.
Set `kuraController.sharedDisk.reserveBytes` high enough to remain above the
actual filesystem/kubelet eviction boundary under non-tenant bursts. Set
`capacityBytes` when an additional tenant cap is needed. There is deliberately
no guessed production reserve. Enable the DaemonSet and label qualified nodes
`tuist.dev/kura-shared-disk=true`. Only then opt the relevant governed region's
provisioner configuration into `shared_disk: true`. This label is required by
both server capacity selection and controller pod placement.

Keep old runtimes and unsupported filesystems on full-claim requests. Enabling
sharing changes pod templates and may invoke existing storage lifecycle logic;
it is not a promise of a rollout without replacement. Qualify existing-volume
conversion separately before enabling a region. To roll back, stop new shared
admissions, reclaim or move until full ceilings fit, then restore full-claim
requests. Never remove quota enforcement while ceilings are overcommitted.

The allocation files are transient node operational state, not new account data
or database records. No new telemetry series are introduced. Existing runtime
pressure counters and agent decision logs expose allocation/reclaim behavior.
Fleet dashboards, inode pressure policy, automatic migration and preflight
qualification of production reserves remain rollout work; the isolated staging
fixture does not qualify those fleet rollout gates.

## Local qualification

Run Go tests from this directory with `go test ./...`; Linux also compiles the
XFS backend and Kubernetes inventory. Rust tests cover authorization validation,
expiry, runtime target changes, reader pins, handover holds and pressure cleanup.
The real filesystem test is `kura/test/e2e/shared-disk/run.mjs`. Run it as root in
a disposable local Linux VM with Node.js, XFS tools and project quota support:

```sh
KURA_BINARY=/path/to/kura KURA_DISK_AGENT_BINARY=/path/to/disk-agent \
  node kura/test/e2e/shared-disk/run.mjs
```

It creates and removes a bounded 16 GiB loopback image, real project quotas,
two memory-bounded runtime processes and an allocator. It tests unused-floor
protection, contention, held unlinked blocks, restart, physical reclaim before
reassignment, recent cache hits, lease expiry and recovery. Logs and JSON evidence
remain in the printed temporary directory; the loop image and processes are
removed. This runs locally and requires no staging or production access.

Use `kura/test/e2e/quota-pressure/resources.mjs` sequentially against baseline
and changed images on the same host for memory, disk, CPU and egress comparison.
Run the baseline normally and set `KURA_RESOURCE_SHARED_DISK=1` for the changed
image. That mode publishes synthetic expiring leases at the same effective
3 GiB ring size, isolating runtime overhead; it does not enforce kernel quotas
or benchmark the host agent. The real-XFS test establishes physical enforcement.
Neither replaces qualification of the intended host's reserve before enabling it.

The [2026-10-28 staging record](../../kura/test/e2e/shared-disk/validation.md)
qualifies real local-path PVCs, the bind-mounted provisioner root, packaged agent,
quota reclaim, restarts and cleanup. It records a small write/CPU overhead and a
remaining read-throughput reduction against main; it is not a no-regression
sign-off or a production enablement. Shared XFS does not use OpenBao or provide
the parked per-tenant LUKS boundary. Keep encryption qualification separate.
