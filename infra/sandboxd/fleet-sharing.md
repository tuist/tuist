# Sharing Linux runner hosts with agent sandboxes

Status: proposal for the next phase. Only the accounting corrections described
below are implemented. The admission, reclaim and warm-capacity policies still
need a decision before implementation or rollout.

## Invariants

CI is the primary use of these hosts. Never evict, resize or stop a runner that
has claimed a job. Never pause a sandbox with an active turn. This means an
already-admitted turn can delay a newly queued CI job until it finishes; an
absolute promise that sandboxes never delay CI would require either interruptible
turns or separate hosts. Admission must make this tradeoff explicit.

A sandbox's memory request is real capacity even while a resize is pending.
Count the largest of requested, allocated and applied container memory until
the kubelet confirms that a shrink landed. Keep a terminating daemon charged
while it drains its VMs.

## Accounting corrected in this change

The fleet byte budget already subtracted sandbox memory. Per-node shape caps and
host reservation now subtract it too, along with the daemon's CPU request. They
read the sandbox namespace through the uncached API reader, because the controller
cache only watches the runners namespace. A failed read prevents reservation and
sandbox-driven preemption; autoscaling retains its existing read-error fallback.

A 64 GiB host with a 40 GiB sandbox allocation has no seat for a 32 GiB runner,
even if another host has enough spare memory to make the fleet-wide sum look
sufficient. A requested growth from 1 to 40 GiB and an unapplied shrink from 40
to 1 GiB both count as 40 GiB. The early reservation path also includes sandbox
memory beside running jobs and checks the waiting Pod's RuntimeClass overhead.
Draining a host cannot free the sandbox allocation.

These are point-in-time calculations. They do not coordinate a later sandbox
resize with a runner reservation; Kubernetes remains the final admission gate.

## Recommended policy

Keep the 1 GiB daemon floor and start with **zero additional warm sandbox
memory**. A template already provides a fast VM start, while a GiB withheld from
CI can remove an entire large runner seat. Do not fund a sandbox p95 buffer until
measurements show that resize latency, rather than queued work or disk, is the
material bottleneck.

Use one fleet allocation decision with this priority order:

1. Memory already held by running CI jobs and active sandbox turns, plus daemon
   floors. This is committed capacity, not something the allocator can reclaim.
2. Dispatchable queued CI demand, with the existing per-shape and per-node fit
   constraints. Work withheld by account concurrency limits is not pressure.
3. Queued sandbox turns that fit after CI demand is funded. A resumed turn must
   fit its existing node; fleet-wide free bytes alone cannot admit it.
4. CI warm floors and recent-demand headroom. Any future optional sandbox warm
   budget competes here, defaults to zero, and yields completely to CI demand.

Keep sandbox demand separate from ordinary `PoolDemand.Load`: that tier currently
grants real load even past fleet capacity, whereas an unacknowledged sandbox turn
can stay queued upstream. Treating both as identical pools would lose CI priority
and admit memory that no node can supply. Export committed and queued sandbox
bytes per node/shape in the existing internal scaling response; do not manufacture
RunnerPool objects for daemon memory.

When dispatchable CI work is blocked on capacity, immediately pause eligible idle
sandboxes on useful nodes and bypass the three-minute growth hold. Reclaim page
cache and request the shrink, but do not spend the released memory until the
kubelet confirms it. The daemon's existing worker/exec guards remain authoritative
if activity races a pause. Busy sandboxes finish their turn normally.

The controller should publish a short-lived per-node allocation and reclaim request
through an authenticated server endpoint. Store desired allocation and generation
in the shared database, and act under the existing node capacity lock. The server
must reject new growth on a CI-reserved node and while its CI allocation is being
reclaimed. Only the controller assigns capacity between substrates; only the
server resizes daemons. Expired or missing coordination data stops new growth,
but never stops existing jobs or turns. A generation check prevents a stale shrink
or growth from overwriting a newer allocation.

Rank growth candidates by available requested memory, then by reclaimable warm
runner memory, with deterministic ties. Compute this from controller-observed Pod
requests, including pending resizes and RuntimeClass overhead. Treat the report as
a hint, not a reservation: verify the allocation under the node lock and retain the
kubelet deferral/try-next-node path. Exclude nodes reserved for CI.

## Disk and CPU

For the first rollout, use explicit bounded disk budgets for sandbox images,
runner caches and host reserve on each physical filesystem. Verify their sum
against the provisioned filesystem, including sandbox templates and the temporary
second memory image written during pause. Do not count free bytes independently
in two services. Refuse new sandbox placement before exhausting the host reserve;
paused sessions remain charged until their files are deleted. A joint dynamic
disk allocator can follow after measured occupancy justifies it.

Keep the existing CPU request initially. Increasing it reserves scheduler capacity
but does not create idle CPU and can remove runner seats. Measure CI CPU contention
before selecting CPU weights, caps or elastic requests. Memory accounting alone
is not proof that sandboxes have no effect on running CI latency.

## Validation and rollout gates

Before enabling an account, publish carve-out requested/allocated/used bytes by
node; resize latency and deferred/failed outcomes; admission refusal reasons;
reclaim latency; and a separate sandbox-driven runner retirement counter. Alert on
sustained CI queue age with reclaimable sandbox memory, pending resize age, and
shared filesystem headroom. Avoid account/session labels on fleet metrics.

Exercise two hosts with different free capacity, concurrent CI reservation and
sandbox growth, stale coordination generations, a controller/server restart,
active-turn protection, failed pause/shrink, and repeated demand/shrink cycles.
Measure CI queue and job latency as well as sandbox startup latency.

Coordinate a staging deployment before replacing its current experiment. Build
matching daemon, guest and controller images and pin their immutable tags. The
controller reaches canary/production through a `runners-controller@` release,
separately from the server/chart. Keep account flags off until both sides and the
metrics are present, then enable the Tuist account first.

Rollback first stops accepting new sandbox work through the account flag. Let
active turns finish and shrink allocations before removing daemons; deleting a
daemon is not a substitute for reclaim. Preserve node-local files needed for
paused sessions. Do not merge the current enabled canary/production chart values
as a substitute for an agreed rollout.
