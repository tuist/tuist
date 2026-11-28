# Sharing Linux runner hosts with agent sandboxes

Status: Queued CI and sandbox work have equal admission priority, with zero
additional warm sandbox memory. Managed overlays deploy the daemons; account flags control access
in canary and production. The controller and server must ship together before
enabling accounts. Prior staging validation covered real sessions, pause/resume
and elastic memory; the newer allocation protocol still needs live verification
during the initial Tuist-account rollout.

## Invariants

CI and sandboxes share these hosts. Never evict, resize or stop a runner that
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

These calculations remain point-in-time observations. Short-lived grants now
coordinate sandbox admission with CI reservations; Kubernetes remains the final
admission gate when other workloads or claims change after a snapshot.

## Admission policy

Keep the 1 GiB daemon floor and start with **zero additional warm sandbox
memory**. A template already provides a fast VM start, while a GiB withheld from
CI can remove an entire large runner seat. Do not fund a sandbox p95 buffer until
measurements show that resize latency, rather than queued work or disk, is the
material bottleneck.

The priority order is:

1. Memory already held by running CI jobs and active sandbox turns, plus daemon
   floors. This is committed capacity, not something the allocator can reclaim.
2. Dispatchable queued CI jobs and sandbox turns have equal priority for
   uncommitted capacity. Both must fit the actual node; a resumed turn must fit
   its existing node. An existing host reservation still protects its waiting
   CI shape, but CI queued elsewhere does not veto every sandbox grant.
3. CI warm floors and recent-demand headroom. Idle, unclaimed warm runners can
   be retired for a deferred sandbox growth even while CI is queued. There is
   no extra sandbox warm pool, p95 buffer or post-turn grace on shared nodes,
   except 20 seconds after a sandbox's last command or exec (see below), and on macOS
   the commands session lease.

Admission is opportunistic, not a global FIFO queue or a guaranteed resource
split. Kubernetes arbitrates competing Pod requests. Keep sandbox demand
separate from `PoolDemand.Load`: it grants real load even past fleet capacity,
while sandbox memory requires a fresh per-node grant. Unknown fleet demand still
fails closed. Claimed jobs, active turns, pending resizes and reserved hosts
remain protected; equal priority does not authorize interrupting any of them.

Each account has a separate sandbox vCPU and memory budget. Existing accounts
start with their Linux CI limits; new accounts default to 32 vCPUs and 64 GiB.
Operators can adjust these in the account's Sandbox concurrency card without
changing CI limits. Creating, resuming and running rows count, including detached
Amp processes; paused rows retain disk but release compute quota. The account
row serializes admission and reservation across replicas before node commands
are sent. Lowering a limit blocks new starts/resumes without stopping running
work. There is no sandbox count: the account's disk limit charges every sandbox
on a node, paused ones included, with its workspace and memory image.

A host reservation or unhealthy node revokes admission and reclaims eligible idle
sandboxes. Once the reclaim has lasted two minutes, it also moves the node's
paused sandboxes to object storage, one upload at a time, with their memory images, so their sessions resume warm on
another node of the same snapshot compatibility (processes kept) instead of
waiting for this one; a resume the node refuses for room does the same for
that sandbox. CI waits on neither: a paused sandbox holds no memory, and its
jail stays until the archive is readable. See the archive
tier in `server/lib/tuist/sandboxes/AGENTS.md`. Reclaim page cache and request a shrink, but do not spend the released
memory until the kubelet confirms it. Worker/exec guards remain authoritative if
activity races a pause. Queue depth alone does not trigger fleet-wide reclamation.

The lexicographically first enabled pool in each fleet publishes per-node grants
through `POST /api/internal/sandboxes/allocation`, authenticated as the exact
runners-controller ServiceAccount. A grant is an admission ceiling, not a request
to grow a daemon. It carries the daemon Pod name, observation timestamp, maximum
memory, currently free memory and a reclaim flag. On a host that also runs a
remote execution worker, each daemon's grant also carries the memory it counted
the other carve-out at; the server takes what that carve-out was asked to grow
by since then off the grant, and both daemons share the host's advisory lock.
Grants expire after 15 seconds.
The database stores them on `sandbox_nodes`, under the node advisory lock, and
rejects older/equal observations. Controller and server clocks must be synchronized;
observations more than one second in the future are refused. Pod replacement
invalidates the old grant. A controller restart or signal failure cannot extend
the last grant. Existing turns continue when grants expire.

The server checks the grant on placement, growth, resume and residency start,
including new turns on a VM still running. Idle API execs also check admission;
execs within an existing residency remain allowed. A CI host reservation revokes
the grant before tainting the node. The two controller reconcilers serialize that
revoke/taint sequence with fresh node snapshot/publication, so an earlier snapshot
cannot reopen the reservation. Revoke failure prevents a new reservation.
Only the server resizes daemons. It holds the node lock during the Kubernetes
write and rechecks the desired Pod/size, so a delayed write cannot overwrite a
newer different size. A released deferred growth also retains all charged guests.
Each resize also reads the Pod's resourceVersion and UID and includes them in the
PATCH, with transport retries disabled. A request still in flight after a timeout
must conflict if a newer resize or Pod replacement already landed.

Every accepted observation transactionally queues an idempotent Oban reclaim job.
Busy sandbox locks are skipped rather than waited on; the next observation retries
them. Shared-node pauses have zero extra grace and enqueue a shrink immediately,
except the pause after a sandbox's last command or exec ends, which waits 20 seconds so
the next command of a run (a sync, then a build) finds it running. The sandbox
holds no residency meanwhile, so pressure from an observation pauses it at once.
There is no three-minute warm hold on Linux. On macOS the commands
residency is kept for ten minutes after the last command instead, as the
agent session's turn: a checkpointed macOS VM can only resume on its own Mac,
so a pause between an agent's commands often meant waiting for that Mac's CI
job. The lease is an admitted turn, so CI pressure does not pause it, and it
costs CI that VM's slot for at most ten idle minutes, like an idle Amp Orb's
turn; it counts against the account's quota while it lasts. Only an in-flight growth can retain its request
for up to 15 seconds while admission waits for it; a pause or CI reclaim bypasses
that interval. The minute cron remains a recovery sweep. A failed shrink is
reported to Oban for retry and remains charged by the controller.

Growth candidates rank by currently free requested memory, then by granted memory,
with node-name ties. The grant adds eligible idle runner memory to free memory and
the daemon's existing charge. It counts all namespaces' Pod requests, allocated
and applied sizes, init containers/sidecars and RuntimeClass overhead. Reserved,
cordoned, unready or pressured nodes and terminating daemons grant no new capacity.
These are hints, not reservations: the server verifies the grant under the node
lock and retains the kubelet deferral/try-next-node path. Runner retirement for
sandbox growth is disabled when CI is queued or its demand is unknown.

## Disk and CPU

For the first rollout, use explicit bounded disk budgets for sandbox images,
runner caches and host reserve on each physical filesystem. Verify their sum
against the provisioned filesystem, including sandbox templates and the temporary
second memory image written during pause. Do not count free bytes independently
in two services. Refuse new sandbox placement before exhausting the host reserve;
paused sessions remain charged until their files are deleted. A joint dynamic
disk allocator can follow after measured occupancy justifies it.

Sandboxes burst, the way [Modal's do](https://modal.com/blog/sandbox-bursting):
each creating, resuming or running Linux agent sandbox boots with 16 vCPUs, is
guaranteed a quarter vCPU per GiB of its memory (the hosts' own ratio), and runs on any idle core of the node's shared pool up
to its vCPUs. Its shape only picks its memory, which stays reserved. It is billed,
at every 30-second node report, for the larger of its guarantee and the
CPU its VM used (`sandbox_usage_events`), plus its memory, at Tuist Runners' Linux rates, and the account's concurrency counts its
guarantee. Guests have no CPU limit. The server raises the daemon's CPU request in place, from the
chart's `sandboxes.cpu` floor up to `sandboxes.maxCpu` (passed to the server, not
the daemons, so changing it pauses no sandbox), to the floor plus those
guarantees, and lowers it as sandboxes pause (`Capacity.sync_cpu/1`, on every
grant and every minute). The request keeps those cores out of exclusive-CPU
runners, which otherwise take whole cores from the pool the guests burst into,
and weighs the guests against the pool's other Pods when it is contended.

Inside the daemon's Pod, each VM runs in its own cgroup (`vm-<id>`, beside the
daemon's own `sandboxd` leaf) with `cpu.weight` a tenth of its guarantee in
millicores, so under contention the guests split the Pod's share in proportion
to their guarantees and one busy sandbox cannot take a neighbour's. Memory stays
limited at the container's cgroup, but each VM's cgroup also accounts its own
(`memory.current`, reported as `memory_current_bytes`) and protects its guest
memory with `memory.low`, so the reclaim the container's limit drives takes the
daemon's page cache before a guest's pages. `memory.low` rather than
`memory.min`: the carve-out is reserved memory plus 512 MiB, so the kernel must
still be able to drop a running guest's clean memory-file pages before it
OOM-kills the container, which `memory.min` forbade. A creator can pick a larger
guarantee for a Linux sandbox (1, 2, 4 or 8 vCPUs: API and MCP
`guaranteed_vcpus`, CLI `--guaranteed-vcpus`). A sandbox is only placed on a
node whose hello offers `cpu_guarantees` if its guarantee fits under the
daemon's CPU ceiling and in the grant's free CPU; a node without per-VM
cgroups, or whose controller reports no free CPU, takes only sandboxes without
a picked guarantee (`Capacity.cpu_room?/2`).

Placement packs agent sandboxes onto the node that already runs the most of
them, while it has room: mostly idle sandboxes burst into each other's idle
cores rather than beside CI jobs that keep theirs busy, and the nodes left
without a sandbox take whole runners.

A growth goes into CPU no Pod requests (`cpu_free_milli` in the grant; an
older controller sends none, and its nodes' requests do not grow) and into CPU
idle warm runners hold (`cpu_reclaimable_milli`), the way memory growths take
idle runners' memory: guarantees outrank warm CI seats, never running jobs. The
kubelet defers the part idle runners hold, and the runners-controller retires
the oldest idle warm runners on the node until their CPU covers it
(`deferredCPU`, the same path as a deferred memory growth). The kubelet judges a
Pod's resize as a whole, so a deferred CPU growth holds up the daemon's memory
growths too: the grant counts the daemon at the CPU the kubelet allocated, and
when a runner claims a job before it is retired, the next sync lowers the
request to what fits. A request is cached only once applied. A guarantee that
fits neither waits for CPU to free up; admission does not wait for it. A shrink
always goes ahead. The runners-controller already subtracts the daemon's CPU request
from its seat accounting.

Production measurements over the week to 2026-11-17 (5-minute rates, before
exclusive CPUs reached every even shape): runner hosts were busy 8-52% at p95
and at most 89%, CPU pressure (PSI some) stayed under 3.3% at p95 and 15% at
most, sandbox guests used up to 9.6 cores on one host and 36 across the fleet,
and a running sandbox averaged 0.54 cores. With at most 7 running sandboxes on a
host, their guarantees reserve under 2 cores, well below the default 8-core
ceiling. A 16-vCPU guest on a host whose shared pool exclusive runners have
shrunk overcommits its vCPUs; that slows bursts, not the guarantee.

## Validation and rollout

The controller exports `tuist_runners_sandbox_memory_bytes{node,kind}` for charged,
grant and free bytes, `tuist_runners_sandbox_grant_timestamp_seconds`, and a separate
`tuist_runners_sandbox_retired_pods_total{pool}`. Server capacity counters and latency
histograms use node/operation/outcome labels for admission refusal, growth deferral,
failure and reclaim. These measure control-plane operations, not end-to-end turns.
Before enabling an account, also verify requested/allocated/used memory from the
Kubernetes/cgroup telemetry and build the corresponding dashboards. Alert on
sustained CI queue age with reclaimable sandbox memory, pending resize age, and
shared filesystem headroom. Avoid account/session labels on fleet metrics.

Exercise two hosts with different free capacity, concurrent CI reservation and
sandbox growth, stale coordination generations, a controller/server restart,
active-turn protection, failed pause/shrink, and repeated demand/shrink cycles.
Measure CI queue and job latency as well as sandbox startup latency.

Coordinate a staging deployment before replacing its current experiment. A
staging deployment from the branch builds the matching daemon and guest images;
build the controller image and pin its immutable tag. The
controller reaches canary/production through a `runners-controller@` release,
separately from the server/chart. Keep account flags off until both sides and the
metrics are present, then enable the Tuist account first.

Rollback first stops accepting new sandbox work through the account flag. Let
active turns finish and shrink allocations before removing daemons; deleting a
daemon is not a substitute for reclaim. Preserve node-local files needed for
paused sessions. Canary and production chart values enable the daemons with
a 1 GiB floor per node. The account flag controls API and
poller access, not the daemon's baseline resources or template prebuilds. Keep
the global flag off and enable only the Tuist account initially, after matching
releases are deployed and grants are confirmed. The generic chart default stays
disabled so self-hosted installs do not deploy privileged daemons implicitly.
