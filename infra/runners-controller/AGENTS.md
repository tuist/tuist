# runners-controller

Kubernetes controller for `RunnerPool` CRDs. Runs in the workload
cluster, reconciles Pods + per-Pod `ServiceAccount`s that the Tuist
server's dispatch endpoint authenticates via the TokenReview API.

Two reconcilers, both on the same `RunnerPool` resource but with
independent workqueues:

- **`RunnerPoolReconciler`** — converges Pods + SAs to match
  `spec.replicas`. Idle Pods (those without the
  `tuist.dev/runner-pool-owner` label) are the only ones eligible for
  scale-down deletion; runners mid-job are never killed. It also owns
  a `tuist.dev/runner-pool-drain` finalizer: deleting or renaming a
  RunnerPool (e.g. a helm pool-topology change) would otherwise let
  GC cascade-delete the owned Pods — busy ones included — so the
  finalizer holds the CR Terminating, reaps only idle Pods, and waits
  for mid-job Pods to finish their single-shot job before releasing.
  When it reaps a terminal Pod it logs the `runner` container's
  `exitCode`/`reason` first — the durable, image-independent post-mortem
  fingerprint for a runner that "lost communication" (0 = clean,
  137+OOMKilled = host OOM, 137+Error = guest OOM / in-VM kill, signal
  15 = SIGTERM, other = crash), captured before the Pod is gone.

- **`AutoscalerReconciler`** — on a 5-second cadence, calls the
  server's `/api/internal/runners/desired_replicas` endpoint and
  patches `RunnerPool.spec.replicas`. The per-pool policy math lives in
  `internal/scaling/desired.go`; tuning knobs (`minWarmPoolFloor`,
  `maxReplicas`, `scaleDownCooldownSeconds`, `holdRecentPeak`) live in
  the `RunnerPool` spec, so a tuning change is helm-only.

  `holdRecentPeak` (default true) keeps a pool sized to the server's
  hourly p95 of concurrent runners after load falls. A pool whose jobs
  arrive in one-off bursts (the `ber1` smoke pool, dispatched by hand)
  sets it false, so after a burst it sizes to load plus
  `minWarmPoolFloor` instead of holding the burst's runners for an
  hour. Explicit `runnersFleet.pools` / `runnersFleetLinux.pools`
  entries render it when their `autoscaling` block sets it.

  **Fleet-capacity awareness.** Both Linux shape pools and macOS Xcode
  pools share a capacity budget across siblings, so their warm capacity
  competes. The reconciler runs the per-pool target through
  `internal/scaling/allocate.go`'s `AllocateFleet`, a three-tier priority
  allocation over the pools sharing `(OS, FleetSelector)`:
  (1) real load (`occupied + queued`), (2) each pool's
  `minWarmPoolFloor` above its load, then (3) the speculative
  95th-percentile buffer above that. `occupied` is the distinct union of
  live claims and open runner sessions, so post-job cache and teardown
  work keeps its host funded after the GitHub completion webhook releases
  the claim. Only
  tier 1 (real load) is inviolable — granted in full even past capacity,
  with the excess going Pending (the "add a host" signal). Tiers 2+3 are
  idle warm capacity and yield under contention — headroom first, then
  floor — to admit another pool's real queued work. So when a starved
  pool has queued jobs that don't fit, an idle pool's warm Pods are
  reaped (its desired drops *below* its floor) to free capacity, rather
  than leaving the queued jobs Pending while idle Pods hold reservations.
  The tradeoff: under sustained load on one pool, other pools' warm
  fleets shrink toward their real load, so a returning spike pays
  cold-start — a job queued now beats a warm Pod for a job that might
  arrive, and the scale-down cooldown damps the reap.

  A tier that cannot be funded in full is split proportionally to cost,
  and the whole Pods the rounding leaves go one per pool per round to the
  pools with the largest target (which includes the hourly peak), then by
  name (`grantRemainder`). Every rack image keeps a one-Pod floor, and
  without this one queued job past capacity rounded every floor to zero:
  all images went cold for one job, and the freed slots sat unassigned.
  Now only as many floors yield as the load needs, least recently used
  image first.

  **Cross-pool preemption** (`controllers/preemption.go`). The cooldown
  damps a pool's own oscillation, but it must not hold idle runners
  while a sibling's queued jobs cannot be placed. When a pool is inside
  its cooldown and the allocator has already lowered it, the autoscaler
  checks its fleet for starved siblings and retires this pool's share of
  idle runners at once instead of deferring:

  - *Starved* means the sibling has Pods the scheduler refused with
    `Insufficient …` for at least `preemptionWait` (30s), backed by
    dispatchable `queued` jobs its own idle bound Pods cannot absorb:
    `min(rejected, queued - idleBound)`. `withheld` work (accounts at
    their concurrency limit) never preempts. Entitlement is not checked
    here: a job is only queued on a site pool when dispatch routed it
    there (`runner_site` accounts, or the pool's own dispatch label), and
    the site spillover worker moves queued jobs off a site that is down.
  - Demand is counted in the allocator's per-Pod cost, minus seats
    already on their way back, so consecutive ticks do not over-preempt
    while a Tart VM tears down. A pool returns the seats it holds above
    its `spec.replicas`, counting Pods deleted within `preemptionSettle`
    that are still on their node. A Pod that finished its job is not
    counted: its pool is already replacing it, and the replacement takes
    the seat.
  - Victims are pools above their allocation that are not starved
    themselves. They give up Pods one per pool per round in name order,
    so every pool's reconcile computes the same split. The cut is taken
    from the smaller of `spec.replicas` and the Pods that exist, so a
    pool still recreating Pods retires every runner it marked. A victim
    never drops below its allocation, so `minWarmPoolFloor` yields exactly as
    the allocator already decides: floors are funded only after every
    pool's real load, so a queued job outranks a sibling's warm floor.
  - Only warm idle runners (`isIdle` + `isWarmCapacity`, the same
    signals the node-drain reap uses) that have been warm for at least
    `preemptionGrace` (2m) are eligible, oldest first, except that runners
    on hosts already holding a starved pool's golden image
    (`tuist.dev/golden-<hash>`) go before all others: the starved Pod takes
    whichever seat frees, and on those hosts its job clones the image
    instead of pulling it. A runner still
    booting, just warm and about to claim, running a job, or on a stale
    template is never chosen. Unbound idle Pods within the victim's
    surplus go too, since they would race the starved Pods for the
    freed seats.
  - The autoscaler annotates the chosen Pods (`tuist.dev/preempted-for`,
    `tuist.dev/preempted-at`), lowers `spec.replicas`, and stamps
    `lastScaleDownAt`. The RunnerPool reconciler's scale-down retires
    marked Pods first, emits `RunnerPodPreemptedForSiblingDemand` on
    each, and counts them in
    `tuist_runners_pool_preempted_pods_total{fleet_selector,pool}`
    (runners dashboard, "Idle runners preempted for a starved sibling
    pool"). A mark older than `preemptionSettle` is ignored.

  Bytes are fleet-wide, like the allocator's budget, so preemption can
  free two small seats on different hosts for a starved 12 vCPU guest
  that needs one whole host. Accumulating a whole host is the node
  reservation's job (below).

  The capacity unit is allocatable memory bytes on both platforms; only
  what the per-Pod cost includes differs:

  - Linux: budget = sum of allocatable memory across nodes labeled
    `node.cluster.x-k8s.io/pool=<FleetSelector>` (scaled by
    `MemReserveFraction`, default 0.9); cost =
    `spec.podMemoryMB` plus the selected RuntimeClass's live
    `overhead.podFixed.memory`. Reading the RuntimeClass keeps the
    allocator aligned with Kubernetes admission and scheduling when
    Kata's virtual-machine overhead changes. If the RuntimeClass
    cannot be read, the autoscaler leaves replicas unchanged rather
    than scaling with an incomplete cost. Pool-list and sibling-signal
    failures still use the independent per-pool target so a transient
    read failure cannot freeze scale-up for queued work. Memory is the
    only dimension — Kata pins it per microVM and CPU is oversubscribed.
  - macOS: budget = sum of allocatable memory across nodes labeled
    `tuist.dev/fleet=<FleetSelector>` + `kubernetes.io/os=darwin`,
    unscaled; cost = `spec.podMemoryMB` (no RuntimeClass — the guest is
    a Tart VM, not a sandboxed container). The quotient is the fleet's
    guest-slot budget, which the allocator apportions across competing
    Xcode pools.

    No reserve fraction here, unlike Linux: `hostMemoryMB` is a number
    the operator picks for tart-kubelet to advertise, already net of
    what Apple's Virtualization.framework holds back, and macOS runs no
    memory-requesting DaemonSets on these Nodes. Scaling it again would
    double-count that reserve and strand a whole guest slot.

    **Slots are not hosts.** One `tuist.dev/fleet` value can span
    several MachineDeployments — that is how a mixed-SKU fleet is
    expressed — so an M2-L advertising 14336 MB contributes one slot
    while an M4-XL advertising 28672 MB contributes two. This is the
    same division kube-scheduler performs when it places the Pod, which
    is the point: the allocator agrees with the scheduler by
    construction rather than via a second number kept in sync by hand.
    Apple's SLA caps any single host at 2 guests and Tart enforces it.

    **Shape placement caps.** The byte budget above answers "how much
    fleet is there", which over-counts as soon as a shape does not fit
    every host. A 12 vCPU / 28 GB guest fits only an M4-XL, yet a fleet
    advertising 157696 MB divides to five such slots when two are real,
    because the sum pools memory from M2-L hosts that cannot seat one at
    all. It also cannot see CPU, which binds a guest whose memory-per-
    vCPU is richer than its host's. So the autoscaler additionally
    computes, per shape, the sum over Ready nodes of each node's OWN
    `min(cpu, memory)` quotient, and `AllocateFleet` caps every pool
    sharing that shape at it.

    This has to be a shared cap rather than `maxReplicas`, because a
    macOS shape renders one pool per Xcode version: five pools each
    capped at the two M4-XL hosts compose to ten. Inside the cap, seats
    go load first, then warm floor, then headroom, one Pod per pool per
    round (so contenders do not both lose a seat) in name order (so the
    split is stable across reconciles).

    Both platforms. It was darwin-only until 2026-09-02, on the grounds
    that kata pins memory and oversubscribes CPU so the byte budget was
    already exact on a homogeneous Linux fleet. Neither half held.
    `podtemplate` sets the runner container's CPU request equal to its
    limit equal to the shape, so kube-scheduler bin-packs on the full
    vCPU and a 16 vCPU Pod costing 16.25 with kata's overhead seats
    exactly once on a 31-vCPU RISE-L, where the byte budget reads three.
    And a fleet-wide byte sum cannot see per-node packing at all: six
    `4vcpu-16gb` Pods fill 111 of a box's 117 GiB, so the leftovers add
    up to budget that seats nothing. On 2026-09-02 the autoscaler
    targeted 67 of that shape where 24 fit, and the excess held the
    provisioning ceiling against every sibling.

    The seat divisor is the *placement* shape (`placementShapeOf`): the
    Pod's own request plus the RuntimeClass `podFixed` overhead the
    scheduler charges at admission. `perPodCost` reads the same overhead
    through the same helper, so the byte budget and the seat cap can
    never disagree about what one Pod costs. Deriving the cap from live
    node allocatable is also why no per-shape `maxReplicas` belongs in
    values: that would be a second copy of this arithmetic, stale the
    moment a box is added, lost, or re-SKU'd.

    **Node reservation.** Runs on BOTH fleets. A shape needing more of a
    host than any single smaller Pod does cannot accumulate the room on
    its own. kube-scheduler does not hold its queue on an unschedulable
    Pod, so each slot that frees is taken by the next smaller Pod that
    fits, and the large Pod waits for a coincidence that a steady
    trickle of small jobs prevents. The cross-pool reclaim does not help
    either: it reclaims speculative warm capacity, and the Pod winning
    the race is backed by real queued work, the one tier that never
    yields.

    On darwin the unit is guest slots: a 12 vCPU Pod needs both of an
    M4-XL's. On linux it is memory: a 64 GiB shape costs 66.5 GiB (the
    shape plus the kata RuntimeClass's 2.5 GiB podFixed), over half of
    a production RISE-L, so it needs a contiguous block that 8 and
    16 GiB Pods keep carving up.
    The linux drain is progressive rather than all-or-nothing — the
    taint stops new Pods landing, running jobs finish and free their
    memory, and the starved Pod is placed the moment its shape fits
    rather than when the host is empty.

    A reservation is never taken on a fleet with fewer than two healthy
    hosts (`healthyNodes`). The taint is NoSchedule for every pool but
    the reserving one, so on a single-host fleet it would stop dispatch
    outright until it cleared. The granularity guard below does not
    cover that case on linux — a 64 GiB shape is genuinely coarse even
    on a lone host, so it passes — and the linux fleet is small enough
    for one host to be a real configuration.

    `fleetNodeSelector` addresses each platform's hosts by the labels
    that platform's Pods select on (`tuist.dev/fleet` on darwin,
    `node.cluster.x-k8s.io/pool` on linux, both paired with
    `kubernetes.io/os`), so the reservation and the scheduler always
    agree on which hosts a fleet has.

    A reservation is only taken for a shape that is LARGE relative to
    the fleet: this shape must get fewer seats on the candidate host
    than the fleet's most granular shape does. That is exactly the case
    where the seats it needs are the ones smaller Pods keep taking. On a
    homogeneous fleet whose hosts hold one guest (the macOS side of
    staging, canary) the test never passes, so the mechanism is inert
    there — nothing can accumulate when the shape already fits a single
    seat, and reserving a one-host fleet would take every pool out of
    service until it cleared. Waiting is correct there, and the
    allocator's cross-pool reclaim already arranges it.

    When a qualifying Pod has sat unscheduled past `reservationGrace`
    (2m), or past `idleHostReservationGrace` (30s) when the best
    candidate holds only idle runners and no seat in flight (draining it
    waits on no job, and with a warm runner per rack image every host of a
    quiet fleet can hold one), the RunnerPool reconciler taints one eligible host
    `tuist.dev/reserved-for=<pool>:NoSchedule`, preferring the host with
    the fewest running jobs and, among those, one already holding the
    pool's golden image. Every runner Pod
    tolerates that key at its OWN pool's value, so the host stops
    admitting everyone else while its seats accumulate. Running jobs are
    waited out, never evicted; only idle Pods of other pools are
    retired, and only once their seat is no longer in flight
    (`seatInFlight`). A Pod that bound within `seatGrace` (2m) is the
    seat some other reservation just produced, and dispatch has not yet
    reached it. A macOS Pod is in flight while it is bound and Pending,
    up to `macOSProvisioningGrace` (20m), because tart-kubelet may be
    pulling the image for minutes before the VM exists, and for
    `macOSClaimGrace` (3m) after its VM starts, so the guest's first
    dispatch poll can claim the job it was created for. Candidate
    ranking counts those seats as occupants to wait out. The
    taint is removed when the Pod lands or after
    `reservationTimeout` (15m), and at most one host is held per fleet
    (`maxFleetReservations`; the count is taken over the pool's own
    fleet nodes, so darwin and linux hold separate budgets), since a
    reservation is capacity withdrawn from the small shapes while it
    converges. On the production Linux fleet, a handful of bare-metal
    boxes, one reservation is already a large share of it, which is why
    the cap stays at one and why `healthyNodes` floors it.

    A timed-out release rests the host for `reservationCooldown` (15m)
    via a `tuist.dev/reservation-cooldown-until` annotation. Without it
    the timeout does nothing: `starvedPod` measures a Pod's own age, so
    the Pod that triggered the reservation is still far past the grace
    period the moment the taint lifts, and the next reconcile would
    re-reserve the same host immediately. The cooldown is on the NODE
    rather than the pool because the host is what is being rested — a
    pool blocked on one host stays free to reserve a different eligible
    one. A release because the Pod landed sets no cooldown; it achieved
    what it was for.

    A dedicated taint, not a cordon: a cordoned node is indistinguishable
    from one Cluster API is replacing, and `reapIdlePodsOnCordonedNodes`
    would retire the reserved pool's own Pod the moment it landed and was
    still warm-polling.

    Three properties the taint being pool-named forces:

      - **Orphans must be swept.** Only the pool named in a taint can
        find and release its own reservation, so a deleted or renamed
        pool would strand the host out of the fleet forever and keep its
        reservation counting against `maxFleetReservations`. The delete
        path releases explicitly (`reconcileDelete` returns before
        reservation reconciliation), and every reconcile sweeps taints
        naming a pool that no longer exists as a backstop.
      - **The fleet limit is confirmed uncached.** `MaxConcurrentReconciles: 1`
        serializes the workers but not their reads; the informer cache
        can lag a taint another pool wrote moments ago. The one path that
        takes the fleet's reservation re-reads nodes through the
        `APIReader` before committing.
      - **Node writes are optimistically locked.** Taints are a plain
        list, so a merge patch replaces the whole array with the one
        computed from our copy. Without a resourceVersion precondition a
        taint added since the read — a kubelet pressure taint, Cluster
        API's cordon, a sibling reservation — is silently dropped.

    Candidate selection subtracts the pool's OWN Pods from a host's
    usable seats. The reaper never retires own-pool Pods, so a host
    already holding one cannot be cleared for a second; ranking on
    occupancy alone made exactly that host look ideal, since its own idle
    Pod counts as zero occupancy.

    PriorityClass preemption cannot substitute. The scheduler picks
    victims by priority, `spec.priority` is immutable after admission,
    and a runner Pod becomes job-owning in place — so a priority high
    enough to evict for the large Pod would also kill customer builds.
    The signal that separates them (`isIdle`) reads init-container
    status the scheduler never sees, which is why this lives in the
    controller.

  Only nodes that report `Ready=True`, remain schedulable, carry no
  `tuist.dev/prewarming` taint (a joining macOS host still pulling its
  runner images; see tart-kubelet's AGENTS.md), and have no memory, disk,
  or process identifier pressure contribute to either budget. A fleet
  filtered to zero capacity still takes the existing per-pool fallback,
  so a transient node roll never triggers a mass scale-down of warm
  Pods. Pod creation has a separate fail-closed healthy-node gate
  described below.

  The reconciler reads nodes via the cluster-scoped `nodes` verb in
  the ClusterRole. Fleet-capacity, pool-list, and sibling-signal
  failures fall back to the per-pool target — a transient read blip
  must never trigger a mass scale-down or block independent scale-up.
  A pool with an unrecognised `OS` (or without autoscaling enabled)
  skips the allocator entirely.

  A macOS Pod is placed before any job is assigned to it, so it also
  prefers a host holding the custom cache volumes of the queued job it is
  created for. The signals carry `preferred_nodes`
  (`VolumeAffinities.preferred_nodes/3`): one Node per oldest queued job,
  in queue order, that holds the job's predicted volumes and whose cache
  disk still has room for them after the jobs already on it. The server
  spends a Node's room as it assigns jobs, so a Node repeats only once per
  job it fits. Idle Pods take the oldest queued jobs, so `createRunner`
  gives the Pod for queue position `len(idleAlive) + i` that position's
  Node as one `metadata.name` term at weight 20 beside the golden
  preference at weight 100 (`podtemplate.PreferCacheVolumeNode`). The
  image still decides and the volume breaks ties. Two Pods created
  together are never both steered to a host whose cache disk holds only
  one job's volumes, which would send the second job's attach cold. The
  term is in no revision, so it never makes a Pod stale, and a Pod past
  the list or created without signals keeps only the golden preference.

  RuntimeClass overhead is copied into `Pod.spec.overhead` only when
  Kubernetes admits a Pod. Helm therefore hashes the Linux RuntimeClass
  name and fixed processor and memory overhead into
  `tuist.dev/runtime-class-revision` on each Linux RunnerPool, and
  `podtemplate.Build` copies that revision to new Pods. A mismatch makes
  an idle Pending Linux Pod stale. The reconciler replaces those Pods
  under `spec.rollout.maxConcurrentPercent`; claimed or Running Pods
  finish naturally. Current-template idle Pods that are not warm consume
  the same availability budget even when ordinary scale-up created them.
  This deliberately follows maximum-unavailable semantics: a scale-up
  can pause a roll rather than letting the controller remove another
  warm Pod while serving capacity is already unavailable.

  An image roll leaves a stale macOS Pod alone while its seat is in
  flight (`macOSSeatInFlight`): reaping it mid-pull, or draining it
  before its first poll, makes the job it was created for wait for a
  replacement to pull the new image. It runs that job on the old image
  and exits like any single-shot runner.

  An image change moves the replaced image to `status.previousImage`.
  tart-kubelet reads it to pull the new image on hosts that hold the old
  one before its GC reaps the old golden, so a release costs those hosts
  the overlay rather than the whole image (see `../tart-kubelet/AGENTS.md`).

  `tuist.dev/runner-operator-drain=true` is an operator-set, one-way
  retirement signal. The controller does not apply or clear it. The
  server returns a drain response before attempting a claim, so an
  idle runner exits through its normal lifecycle and the reconciler
  replaces it. Removing the label before the runner's next dispatch
  poll cancels the retirement; after the runner observes it, the Pod
  is expected to exit and be replaced.

  **Linux Kata provisioning admission.** Capacity and creation velocity
  are separate safety boundaries. A queue spike can fit within the
  fleet's memory budget while still asking kubelet and Kata to start too
  many sandboxes together. Before filling a Linux Kata pool's replica
  gap, `RunnerPoolReconciler` counts every alive, unclaimed Pod whose
  dispatch poller has not started across sibling pools sharing
  the same operating system and `FleetSelector`. It creates only up to
  the fleet ceiling, `spec.provisioning.maxConcurrentPerNode` (default
  6) times the fleet's healthy node count, using the lowest sibling
  per-node value so one mismatched pool cannot weaken the fleet
  boundary. Excess demand remains a replica gap and is retried every
  five seconds. macOS pools skip this gate.

  The budget is per node because what it protects is per node: each host
  runs its own kubelet and its own Kata runtime, and a simultaneous
  sandbox-start burst overwhelms one of them, not the fleet. Expressed
  fleet-wide it did the opposite of its job — adding hardware raised
  capacity without raising start throughput, so the fleet could be
  simultaneously idle and refusing work. Measured on 2026-09-03: 62 jobs
  queued across the Linux pools, one node at 0% CPU and 0% memory and
  two more near half, every pool refused with `reason="fleet_cap"`, and
  raising the ceiling by hand filled the idle machines inside one
  reconcile tick (`linux-4vcpu-16gb` went from 1 Pod to 18).

  The per-node figure is what bounds how fast queued Linux work can
  start: the fleet's fill rate is the ceiling divided by sandbox boot
  time. Three per node was measured saturated on 2026-09-03, refusing
  admission 737 times in ten minutes while the four hosts sat at 0-17%
  CPU and 1-37% memory and boots completed in 82s to 3m37s with no start
  timeouts, so both the hosts and the 300s budget had room. Hence 6.
  `tuist_runners_pool_pod_start_timeouts_total{reason="poller_not_started"}`
  is the signal that says whether there is still room: flat means boots
  sit comfortably inside the timeout, rising means a host is already
  being asked for more microVMs than it can start and a bigger budget
  would only turn refusals into timeouts.

  The node count is `summarizeFleetNodes`, so it already excludes
  cordoned, NotReady and pressured nodes. That is deliberate and it is
  what makes the documented remedy below — cordon a host that accepts
  sandboxes it cannot start — take that host's share of the start budget
  away with it, instead of leaving the ceiling inflated by a node
  contributing nothing.

  The field replaces `maxConcurrentPerFleetSelector`, which was a single
  fleet-wide integer. Nothing reads the old name: structural-schema
  pruning drops it from any CR that still carries it, including the
  value patched onto production by hand during the 2026-09-03 incident.
  No operator step is needed for the schema: `server-deployment.yml`
  runs `kubectl apply -f crds/` before every helm upgrade, precisely
  because helm skips `crds/` on upgrade, so the new schema lands with
  the deploy. The Go default, the CRD default and the chart value are
  still kept equal, so that a cluster whose schema has somehow not
  caught up prunes `maxConcurrentPerNode` on the way in and lands on the
  same figure through the accessor instead of an older one.

  The count deliberately includes Pods with no node. An unbound Pod is
  one the scheduler may bind at any moment, and nothing re-checks
  admission between that bind and the sandbox start, so discounting
  unbound Pods would let a backlog build and then start all at once when
  capacity returns — the very burst the ceiling exists to prevent.
  Scheduling gates do not help here either: a gate can be removed but
  never re-added, so a Pod that turns out to be unschedulable after
  ungating is back to holding a slot with no way to reclaim it.

  A ceiling that scales with the fleet bounds how many sandboxes are
  coming up across it, but not how many land on one host — this
  controller does not place Pods, and steering them was tried and
  dropped (see the per-node circuit breaker below). What it can bound is
  how many are handed to the scheduler at once, and the Pods with no
  node yet that the scheduler has *not* rejected are exactly the set
  that can arrive on one kubelet together: kube-scheduler prefers the
  least-allocated node, which on a fleet with an idle host means all of
  them. So that set is capped at one node's budget, refused with
  `reason="placement_burst"`. It costs nothing in steady state — those
  Pods bind within a second or two, well inside the five-second tick —
  and it makes a batch of creations converge on the ceiling over a few
  ticks rather than landing as one burst.

  So `placement_burst` on `tuist_runners_pool_admission_blocked_total` is
  what a healthy ramp looks like, not a fault: a pool with a gap of 19
  reports it on every tick until the gap closes. A *sustained* one with a
  queue behind it means the Pods are not binding, which is the
  unschedulable reap's territory. The same counter reports whichever term
  actually capped the tick, not only outright refusals — that is what
  `limitedBy` is for. Attributing a ramp to the ceiling would leave
  `fleet_cap` meaning nothing.

  A Pod the scheduler has already refused is excluded from that set,
  though it still holds its slot in the ceiling. It is not about to
  arrive anywhere; it binds one at a time as capacity frees. Counting it
  would rebuild the 2026-09-02 starvation on the new gate, with a shape
  no node can seat parking its Pods for a whole start timeout while
  every sibling is refused behind them.

  The ceiling is shared, so it is also divided. A pool's own share
  (`poolCap`) is the fleet ceiling minus one for every sibling pool that
  has a replica gap and nothing provisioning; it never drops below one.
  A pool at its share is refused with `reason="pool_share"` even when
  the fleet count is under the ceiling. Without this, the first pool to
  fill the budget kept it: on 2026-09-02 `linux-4vcpu-16gb`, targeted
  far above what the fleet seats, held all four slots with Pods
  Pending on `Insufficient memory`, recreated each one the instant the
  unschedulable reap released it, and `linux-2vcpu-8gb` was refused
  creation for over an hour with 143 jobs queued. The fleet count is
  still what bounds the burst; the share only decides who may top it
  back up after a reap, so the reap that already existed becomes the
  moment a starved sibling gets its slot, within one
  `startTimeoutSeconds`.

  The share has to be taken out of the ceiling siblings are measured
  against, not just out of their own Pending counts. Bounding each pool
  individually leaves nothing holding a slot open: several pools each
  comfortably inside their own share still fill the ceiling between them,
  and the fleet check refuses the starved pool before its reserved share
  is ever read. On 2026-09-03 `linux-4vcpu-16gb` sat at zero Pods with
  `pendingForPool: 0, poolCap: 4, gap: 19` — its whole share unused and
  still blocked — while three siblings held 1, 1 and 2 of the four slots.
  So a pool that is itself owed a slot measures against the full ceiling
  (`fleetCap == cap`) and every other pool measures against the ceiling
  minus the slots its starved siblings are owed, floored at one so a fleet
  where everything is starved still makes progress one Pod at a time.

  A Pod deleting for longer than its grace period plus five minutes is
  force-deleted with a warning event. A Kata sandbox whose shim never
  tears the VM down leaves the Pod Terminating with its containers still
  `running`, and nothing else in the controller can see it: `isAlive`
  excludes a deleting Pod, so it is neither a replica nor a provisioning
  Pod, the pool reads as having a gap, the node reads as full, and the
  two facts never meet. On 2026-09-03 two of four Linux runner nodes were
  held this way for four hours, 94% reserved by Pods doing no work. The
  ordinary reap cannot clear it — a plain `Delete` is a no-op on a Pod
  that already carries a deletionTimestamp — so the object is dropped
  outright. The sandbox can outlive the object, leaving the node
  oversubscribed against what the scheduler believes, which is why the
  reap logs the node and raises an Event: a node producing these
  repeatedly wants draining, not another force delete. Watch
  `tuist_runners_pool_stuck_terminations_total`.

  Pod creates are visible to the cached client asynchronously. The
  reconciler therefore keeps a 30-second in-process reservation for each
  successful create and counts it until the cache observes the Pod. This
  prevents an immediate reconcile from admitting a second full batch in
  the cache-lag window. The controller keeps its default single reconcile
  worker; raising that concurrency requires revisiting the admission
  invariant.

  A Linux Pod that is bound to a node but whose poller has not started
  within `spec.provisioning.startTimeoutSeconds` (default 300, 0 disables)
  is reaped with a warning event and node-condition log.

  A Pod the scheduler has been rejecting (`PodScheduled=False`, reason
  `Unschedulable`) for that same duration is reaped too, timed from the
  condition's `LastTransitionTime`. Recreating it cannot conjure
  capacity, and that is not the point: it holds a slot in the fleet-wide
  ceiling that it will never convert into a running sandbox, and nothing
  else releases it, since the bound-Pod timeout above cannot fire on a
  Pod with no node. Left in place, one pool whose shape no node can fit
  holds the whole `FleetSelector`'s budget indefinitely and every
  sibling shape reconciles at `observed: 0` forever, with queued jobs
  and healthy dispatch. Reaping returns the slot; the replica gap is
  untouched, so the pool retries and simply goes unschedulable again
  while the shortfall lasts, at a rate the timeout bounds. The two reaps
  are distinguished on
  `tuist_runners_pool_pod_start_timeouts_total{reason}` as
  `poller_not_started` and `unschedulable`; a rising `unschedulable`
  rate is a capacity shortfall for that shape, not a boot fault.

  **Known limitation: reaping does not help when the cause is the node.**
  The replacement Pod is scheduled independently, and a node that cannot
  start sandboxes is also the emptiest node in the fleet, so the
  scheduler prefers it and the replacement lands right back on it. The
  ceiling then stays saturated by Pods that can never run, and every
  sibling shape sharing the `FleetSelector` is refused admission with
  `reason="fleet_cap"` for as long as the node stays broken.

  This is what happened on 2026-08-13: one Linux node hit cgroup
  exhaustion after 85 days of uptime and failed every new sandbox with
  `mkdir /sys/fs/cgroup/kubepods.slice/...: no space left on device`.
  Kubelet reports that per Pod, so the node stayed `Ready` with no
  pressure condition and `nodeFilterReason` saw nothing wrong. Four dead
  Pods held the whole ceiling, the autoscaler asked for 160 replicas
  against 5 running, and ~111 jobs queued over 5.5 hours until an
  operator cordoned the node. The leak itself is fixed (see the cgroup
  section below), but the amplification is a property of the ceiling, not
  of that particular fault — any node that accepts Pods it cannot start
  reproduces it.

  A per-node ceiling softens this without removing it. The dead Pods now
  hold one node's budget rather than the whole fleet's, so siblings keep
  creating on the healthy hosts instead of stopping dead; and cordoning
  the broken node, still the remedy, now also removes its contribution
  to the ceiling rather than leaving phantom budget behind. What has not
  changed is that the replacement Pod keeps landing on the broken node,
  so its share of the budget stays burnt until an operator intervenes.

  A per-node circuit breaker was built and then deliberately dropped:
  counting `poller_not_started` timeouts per node and steering new Pods
  away with a required `kubernetes.io/hostname NotIn` affinity. It works,
  but on a two-node fleet the failure mode is worse than the problem.
  Quarantining both nodes blocks admission on `no_healthy_node` *and*
  leaves every created Pod unschedulable, and false positives are
  plausible because `startTimedOut` measures from bind and so counts
  image-pull time — three slow pulls inside the window are
  indistinguishable from a broken node. Bounding it to a minority of the
  fleet makes it safe but also makes it a no-op on two nodes, which is
  the fleet we have. Detection was kept instead: the queue-age alert in
  `infra/helm/k8s-monitoring/alerts.md` catches this shape within
  ~30 minutes regardless of cause, and the remedy is a manual cordon.
  Revisit the breaker if the fleet grows past a handful of nodes, where
  quarantining one is cheap and the manual cordon does not scale.

  Claimed Pods and Pods whose poller has terminated are protected.
  Terminal cleanup and idle scale-down run before admission and are never
  blocked by the provisioning ceiling.

  **Allocation observability (`internal/metrics`).** Each tick the
  reconciler publishes the squeeze on the controller's existing
  `--metrics-bind-address` endpoint, per `pool`:
  `tuist_runners_autoscaler_target_replicas` (the pool's full ask, pre-
  allocation), `..._allocated_replicas` (what it got = `spec.replicas`),
  `..._min_warm_floor_replicas` (configured `minWarmPoolFloor`), and
  `..._warm_deficit_replicas` — the warm floor the allocator wanted to
  fund but couldn't under contention (`max(0, min(load+floor, target) −
  allocated)`, clamped so load starvation isn't counted). The deficit is
  the leading indicator for cold boots: alive-vs-desired only shows the
  pool converging to the *already-squeezed* target, never the squeeze
  itself. Series are dropped (`metrics.Clear`) when a pool is deleted or
  opts out of autoscaling.

  `RunnerPoolReconciler` also publishes
  `tuist_runners_pool_phase_replicas{pool,phase}` for alive Pods by
  Kubernetes phase (`Pending`, `Running`, `Unknown`). This preserves the
  runner dashboard's macOS ready vs cold-booting split without relying
  on pod-scoped kube-state-metrics series.

  Provisioning safety publishes
  `tuist_runners_pool_pending_provisioning_pods{pool}`,
  `tuist_runners_pool_admission_blocked_total{pool,reason}`,
  `tuist_runners_fleet_ready_nodes{fleet_selector,operating_system}`,
  `tuist_runners_fleet_filtered_nodes{fleet_selector,operating_system,reason}`,
  `tuist_runners_fleet_provisioning_ceiling{fleet_selector,operating_system}`,
  `tuist_runners_pool_pod_start_timeouts_total{pool,reason}`,
  and `tuist_runners_pool_stuck_terminations_total{pool}`. The ceiling is
  the derived budget the admission gate measures against, so it moves
  with the healthy node count on its own: a drop with no chart change
  means nodes left the fleet, and comparing it against the summed
  pending-provisioning gauges says how much of the budget is in use. The
  last one
  counts Pods force-deleted because kubelet never finished terminating
  them; it is distinct from the start-timeout counter because that means
  a sandbox failed to come up, while this means one failed to go down and
  may still be holding its node.

  Alongside it, `tuist_runners_pool_oldest_pending_pod_age_seconds{pool}`
  is how long the pool's oldest un-`Running` Pod has been waiting (0 when
  none). **darwin pools only.** On a Tart pool a Pod is `Pending` from
  creation until tart-kubelet has its VM up, so this is the boot path's
  queue age. On a Linux pool `Pending` is the *healthy steady state* —
  the dispatch poller is an init container and kubelet holds a Pod in
  `Pending` for as long as any init container runs — so publishing it
  there would peg every idle pool at its warm-pool age. A Linux
  equivalent has to read the poller's own lifecycle, not the Pod phase.

  The phase count above can't stand in: a pool steadily replacing
  single-shot runners and a pool with one Pod wedged for hours both read
  `Pending=1`. Neither can tart-kubelet's
  `tart_kubelet_pod_provision_delay_seconds`, which is observed when a VM
  finally starts and so omits Pods that never boot entirely — the failure
  this gauge exists to catch, and one that leaves the Node `Ready` and
  `kube_pod_status_unschedulable` at 0 throughout.

  **Starvation vs saturation.** `..._autoscaler_claimed_jobs{pool}`,
  `..._autoscaler_occupied_runners{pool}`, and
  `..._autoscaler_queued_jobs{pool}` publish the server's demand signals
  unsummed, and `tuist_runners_pool_idle_replicas{pool}` counts
  alive current-template Pods with no `tuist.dev/runner-pool-owner` that
  can actually accept a job right now. "Can accept" is OS-dependent, for
  the same reason the un-booted age above is darwin-only: only `Running`
  counts on a Tart pool, because a Pod still waiting on a Mac mini has no VM
  and is not capacity however long it has been alive; on Linux `Pending`
  counts, because that is where a warm dispatch poller spends its whole
  idle life. Getting this wrong inverts the reading — a fleet starved of
  hosts would report idle Pods sitting on queued work, which is the
  fingerprint of the opposite failure.

  On darwin `Running` is necessary but not sufficient, so the guest's own
  heartbeat is consulted on top of it. tart-kubelet synthesizes a macOS
  Pod's phase and Ready condition from "the VM process is alive and has an
  IP" and runs no container probes, so a guest whose dispatch poller died
  reads 1/1 Running for the rest of the VM's life — and nothing bounds
  that life, since warm standby is deliberately unbounded and a warm macOS
  runner is in practice recycled only when its SA token expires around the
  8h mark. `dispatch-poll.sh` therefore beats into the per-VM status share
  every poll and tart-kubelet republishes it as
  `tuist.dev/runner-heartbeat-state` (`polling` / `claimed`) plus
  `tuist.dev/runner-heartbeat-at`; a `polling` beat older than
  `guestHeartbeatStaleAfter` stops counting. Linux needs none of it — the
  poller is an init container, so the container runtime already reports
  whether it is running.

  **Absence is not death.** A Pod carrying no heartbeat annotations is one
  the host cannot speak for: pools with the cache-volume feature off have
  no status share to read, and runner images from before the guest wrote a
  beat produce none. Those keep their benefit of the doubt. Reading
  absence as dead would drop every such Pod out of warm capacity at once,
  which besides being wrong also stalls rolls fleet-wide, because
  `isWarmCapacity` decides what counts against the roll's availability
  budget. The image and the controller can therefore ship in either order.

  Together they separate two failures that every other series conflates:

  - **Saturated**: `queued > 0`, `idle == 0`. Real work exceeds hosts.
    The fix is capacity.
  - **Starved**: `queued > 0` *and* `idle > 0`, sustained. Warm Pods are
    polling dispatch and getting nothing while jobs wait. The fix is
    server-side; adding hosts changes nothing.

  The second state should be impossible — an idle Pod polls continuously,
  so queued work reaches it within a poll interval — which is what makes
  the overlap a reliable fingerprint, **provided `queued` counts only
  dispatchable work**. Raw queue depth includes jobs held back because
  their account is at its platform concurrency limit; dispatch will never
  hand those out, so with a raw count the overlap is a valid steady state
  rather than a fault. The server caps each account's contribution at its
  remaining concurrency headroom before exporting the count (tuist/tuist#11981),
  which is what makes `..._queued_jobs` trustworthy here. Nothing else shows it: the phase
  count reads a warm idle Pod and a Pod running a customer job
  identically (both `Running`), `occupied+queued` stays flat while work
  drains normally (`queued` → `claimed` → post-job occupancy), and the
  oldest-un-booted-Pod age above only sees Pods that never booted, not
  booted Pods that never received work. The `Runner queue age` alert
  fires on either state, so it says something is wrong without saying
  which lever to pull.

  Pod-level autoscaling only. The bare-metal box count is operator-
  managed, since the boxes are pre-ordered monthly contracts that
  nothing here orders. To grow capacity, the operator orders and
  preps another box and raises `ovhFleets.runners-linux.replicas`
  (see "Bringing up a new box" below).

## Machine-metrics sampling (in-VM, not in the controller)

Runner-job machine metrics (CPU/memory/network/disk for the Metrics
tab) are sampled **inside the runner VM**, not by this controller. An
earlier design had the controller scrape each node's kubelet
`/stats/summary` through the apiserver node proxy, but that source is
unavailable in this cluster — the macOS Tart fleet's custom kubelet
doesn't serve the cAdvisor Summary API, and the Linux kata nodes reject
the proxied request — so it produced nothing. Sampling now lives in the
runner images (`infra/linux-runner-image`, `infra/runner-image`): a
loop reads the VM's own `/proc`+cgroup (Linux) or `vm_stat`/`netstat`
(macOS) and POSTs to `POST /api/internal/runners/pods/:pod_name/metrics`
with the runner's own per-pod SA token (audience
`tuist-runners-dispatch`). On Linux the token is isolated from the
customer container, so the sampler runs as a dedicated native sidecar
that mounts the token and shares the pod's cgroup/network namespace.

## Linux runner substrate: OVH bare-metal boxes (kata-qemu)

Linux runner Pods run as QEMU microVMs through Kata Containers on
pre-ordered OVH bare-metal boxes in Gravelines (`gra`): RISE-L (Ryzen 9
9950X, 16c/32t, 128 GB) in production, RISE-S (Ryzen 7 9700X, 8c/16t,
64 GB) in staging and canary. Each env declares the fleet as
`ovhFleets.runners-linux` in `infra/helm/tuist/values-managed-<env>.yaml`,
whose `replicas` is the box count. The chart
(`infra/helm/tuist/templates/ovh-fleets.yaml`) renders it as an
`OVHDedicatedMachineTemplate` plus a `strategy: OnDelete` MachineDeployment
named `tuist-tuist-ovh-fleet-runners-linux`, and
[cluster-api-provider-tuist](../cluster-api-provider-tuist/AGENTS.md)
adopts and self-joins the boxes.

The RuntimeClass is `kata-qemu`
(`infra/helm/tuist/templates/kata-qemu.yaml`, rendered when
`kataContainers.enabled`). Kata runs QEMU rather than Firecracker because
Firecracker has no virtio-fs or 9pfs: `kata-fc` would need a block-device
snapshotter (nydus) to hand the container rootfs to the guest, while
`kata-qemu` shares containerd's default overlayfs snapshot over virtio-fs.

```
operator pre-orders a RISE box in gra (OVH console, OVHcloud US entity)
        │
        ▼
`mise run baremetal:prep-ovh` installs Ubuntu 24.04 (mirrored root +
XFS /data) with the fleet SSH key, then sets the box's displayName to
`tuist-runners-ovh-<env>…` as its last step
        │
        ▼
operator raises `ovhFleets.runners-linux.replicas` and deploys; the
MachineDeployment creates an OVHDedicatedMachine
        │
        ▼
cluster-api-provider-tuist claims the named box and runs the Linux
self-join over SSH as `ubuntu`: containerd, kubelet, `kubeadm join`.
`machine.kataRuntime: true` adds kata-static 3.30.0 under /opt/kata
(bundles qemu-system-x86_64), the kata-qemu handler in
/etc/containerd/config.toml (`SystemdCgroup = true`), and a /dev/shm
ceiling of MemTotal for virtio-fs guest memory
        │
        ▼
Node registers with `node.cluster.x-k8s.io/pool=runners-linux`,
`katacontainers.io/kata-runtime=true`, `tuist.dev/kata-runtime=true`,
and taint `tuist.dev/runner-tier=bare-metal:NoSchedule`
        │
        ▼
runner Pods schedule: the pool's `spec.runtimeClass: kata-qemu` becomes
`runtimeClassName: kata-qemu`, the RuntimeClass selects on
`katacontainers.io/kata-runtime=true` and charges its `podFixed`
overhead (250m CPU, 2560 MiB) per Pod, and each Pod boots its own
guest kernel
```

The runtime is in place before kubelet first registers the Node, so there
is no runtime DaemonSet and no containerd restart after the join. A node
without `katacontainers.io/kata-runtime=true` never matches the
RuntimeClass, so runner Pods stay Pending rather than fall back to runc.

Kata is a bootstrap-time capability: the self-join renders it once, and
`OnDelete` means a values or provider change never rolls a live box. The
provider's Ready-path repair (`reconcileLinuxKataRuntimeDrift`) installs
kata in place on a box that joined without the label and re-verifies the
shared-memory setup after each boot, reporting both through the
`KataRuntimeReady` condition. It does not rewrite an existing kata-qemu
handler block (the append is skipped when one is present), so a change to
the handler config reaches only boxes bootstrapped after it. See
"Bootstrap-time capabilities, and the once-at-bootstrap trap" and "A
Linux runner box is Ready but takes no jobs" in the provider's AGENTS.md.
The kata release is `kataVersion` in
`infra/cluster-api-provider-tuist/controllers/linux/linux_cloudinit.go`.

Hetzner Robot bare metal (caph plus
[hetzner-robot-controller](../hetzner-robot-controller/AGENTS.md)) backs
no runner pool. The `bare-metal-worker` class in
`infra/k8s/clusters/clusterclass-tuist.yaml` and its templates in
`infra/k8s/clusters/bare-metal.yaml` still exist, but no workload cluster
topology uses that class; Robot hosts back only the `stateful-worker`
ClickHouse pool (`md-clickhouse`). Their mgmt-cluster Secrets and
emergency SSH access are in the hetzner-robot-controller AGENTS.md.

### Fleet credentials

Per env, in the `tuist-k8s-<env>` 1Password vault
(`tuist.1password.com`), one item per title:

- `OVH_API` (`application-key`, `application-secret`, `consumer-key`): the
  OVH API token, minted on OVHcloud US (`endpoint: ovh-us`), which every
  OVH fleet in an env shares.
- `OVH_FLEET_SSH` (`private-key`, `public-key`, `sudo-password`): the
  fleet key. ESO syncs it to the fleet's `<fleet>-ssh` Secret
  (`sshExternalSecret.enabled: true`); the prep task reads it from
  1Password directly.

The token's required scopes and a pre-filled minting link are in "Bring
a pre-ordered bare-metal box into the pool (OVH)" in the provider's
AGENTS.md.

### Bringing up a new box (operator workflow)

1. **Pre-order the box** in the OVH console: RISE-L for production,
   RISE-S for staging and canary, in a `gra*` datacenter. The EU plan
   codes (`25risel01-v1-eu`, `25rises01-v1-eu`) are orderable on OVHcloud
   US. Stock per plan and datacenter needs no token:
   `GET https://api.us.ovhcloud.com/1.0/dedicated/server/datacenter/availabilities`.

2. **Prep it.** Installs Ubuntu with the fleet key and sudo password
   (async, ~20-40 min), then names the box into the pool:

   ```bash
   PREP_NAMESPACE=tuist-<env> mise run baremetal:prep-ovh <service-name> tuist-tuist-ovh-fleet-runners-linux
   ```

   `PREP_SKIP_MARK=1` stages the box without naming it;
   `baremetal:mark-ovh` names it later.

3. **Raise `ovhFleets.runners-linux.replicas`** in
   `values-managed-<env>.yaml` to the new box count and deploy. It must
   equal the number of prepped and named boxes: too high parks the
   MachineDeployment short of its replicas and wedges `helm --wait` into
   an `--atomic` rollback; too low leaves a named box billing with nothing
   adopting it. The provider claims the box and self-joins it in ~2-5 min.

Pod capacity follows on its own: the autoscaler derives what each shape
can seat from live node allocatable (`shapePlacementCaps`).
`runnersFleetLinux.shapeAutoscaling.maxReplicas` is a per-pool safety
ceiling, not a capacity bound; raise it only if the ceiling itself binds.

To **watch** progress (`<namespace>` is `tuist` in production,
`tuist-<env>` elsewhere):

```bash
kubectl -n <namespace> get ovhdedicatedmachine -w
kubectl get nodes -l node.cluster.x-k8s.io/pool=runners-linux \
  -L katacontainers.io/kata-runtime
```

A Node is ready for runner Pods once it carries
`katacontainers.io/kata-runtime=true` and its OVHDedicatedMachine reports
`KataRuntimeReady=True`.

### cgroup leak on kata nodes

kubelet runs `cgroupDriver: systemd`, so the kata-qemu handler must set
`SystemdCgroup = true` in its own options block. Without it the kata shim
writes the systemd slice name kubelet hands it as a literal directory at
the cgroup root
(`/sys/fs/cgroup/kubepods-burstable-pod<uid>.slice:cri-containerd:<id>`)
instead of nesting it under `kubepods.slice`. Nothing owns those: systemd
never knew about them and the shim does not remove them, so they
accumulate one per container start. At exhaustion every cgroup `mkdir`
returns ENOSPC, and the node keeps reporting `Ready` while failing every
new Pod sandbox. A busy node reached ~65k of them, against ~70 on a
freshly booted one. The self-join (`kataSetup`) sets it on the handler
block it appends.

**There is a second population of the same size:**
`/sys/fs/cgroup/kata_overhead/*`, one per sandbox, named by container ID.
Same shape (flat empty leaves), same one-per-container-start growth,
never reclaimed. Whether `SystemdCgroup = true` also stops it is **not
established**: the overhead cgroups are created by the shim either way.
Sweeping only the root population leaves the node at half its leak and
reads as a stuck reclaim.

Check a host without SSH. The count should be in the hundreds, not
thousands:

```bash
kubectl get --raw "/api/v1/nodes/<node>/proxy/metrics" | grep node_cgroups_cgroups
```

`node_cgroups_cgroups{subsys_name="memory"}` is alerted on at 20000; see
"Node leaking cgroups" in `infra/helm/k8s-monitoring/alerts.md`. The
alert counts cgroups, not directory names, so it covers both populations.

**Reclaim the leaked cgroups in place, no reboot, no drain.** The leaked
directories are flat leaves: no child cgroups, no processes, owned by
nothing. `rmdir` removes them and the kernel reclaims the underlying
cgroup objects roughly 1:1, asynchronously. The sweep is safe by
construction. For the root population the path is the guard: a
correctly nested cgroup lives under `kubepods.slice`, so anything
matching `*:cri-containerd:*` at the cgroup *root* is leaked. Under
`kata_overhead` every child is a candidate. In both cases skipping a
non-empty `cgroup.procs` leaves live sandboxes untouched, and an in-use
cgroup would fail `EBUSY` anyway.

**Verify with the directory count, not `/proc/cgroups`.** Directory
counts drop immediately. `/proc/cgroups` lags by tens of seconds and
keeps counting cgroups whose directory is gone but whose charges are not
yet reclaimed, so a clean host can read 1500 there while holding 65
directories.

For a node that can still start Pods, no SSH is needed:

```bash
kubectl debug node/<node> --image=busybox --profile=sysadmin -q -- \
  sh -c 'for p in /host/sys/fs/cgroup /host/sys/fs/cgroup/kata_overhead; do
           cd "$p" || continue
           for d in *; do
             [ -d "$d" ] || continue
             case "$p" in */kata_overhead) ;; *) case "$d" in *:cri-containerd:*) ;; *) continue ;; esac ;; esac
             [ -s "$d/cgroup.procs" ] && continue
             rmdir "$d" 2>/dev/null
           done
         done'
```

**A fully wedged node cannot be swept this way.** Creating the debug Pod
is itself a Pod creation, so it fails with the same error the node is
failing everything else with:

```
FailedCreatePodContainer: unable to ensure pod container exists: failed to
create container for [kubepods besteffort pod<uid>] : mkdir
/sys/fs/cgroup/kubepods.slice/.../kubepods-besteffort-pod<uid>.slice:
no space left on device
```

The Pod sits `Pending` indefinitely. On such a host go in over SSH
("Emergency SSH access" below) and run the sweep directly. Prefer
`python3` over a shell loop there: at 65k entries a `kubepods-*` glob
exceeds `ARG_MAX`, so `ls -d <glob> | wc -l` reports **0** rather than
failing loudly, and a shell loop forks `rmdir` once per directory. Count
with `ls | grep -c ':cri-containerd:'` instead. A swept node keeps
running its Pods and takes new ones within a minute; no reboot is needed.

### Replacing a runner box without killing CI jobs

Replacing a box means deleting its Machine: the fleet MachineDeployment
is `strategy: OnDelete`, so nothing else rolls one, and lowering
`ovhFleets.runners-linux.replicas` deletes a Machine the same way.
Cluster API core never drains a Machine in the workload clusters. Their
CAPI `Cluster` has no control plane Machines, so Machine deletion skips
the drain, and with it every `MachineDrainRule`, and goes straight to
the `OVHDedicatedMachine` (the CAPI controller logs `Skipping deletion
of Kubernetes Node ... cause="no control plane members"`). The
provider's release deletes the Node and reinstalls the box, which kills
whatever still runs there, so it waits for the box's CI jobs first. Two
pieces make that wait, and neither works without the other:

1. **The release wait** (`holdReleaseForRunnerJobs` in
   `infra/cluster-api-provider-tuist/controllers/linux/runner_jobs.go`)
   cordons the Node and holds the release while any Pod labeled
   `tuist.dev/runner=true` in `tuist-runners` on it has not reached a
   terminal phase. It never evicts them. Runner Pods are single-shot
   (`RestartPolicy: Never`, one `workflow_job`, then exit), so a Pod
   running a job completes on its own.
2. **The idle reap** (`controllers/node_drain.go`) retires idle Pods on
   a cordoned node. Without it the wait never converges: an idle Pod
   is a dispatch poller with nothing to finish, so it would hold the
   release forever, and the cordon stops new Pods landing without
   removing the ones already bound. Idle Pods are pure warm capacity,
   so retiring them costs only a cold start and the autoscaler
   replaces them on a node that can still accept Pods.

The reap reads `isIdle`, **not** the `tuist.dev/runner-pool-owner`
label. This is also why a PodDisruptionBudget cannot do this job: a PDB
selects on labels, and that label is best-effort. The server degrades
to running a job without it rather than dropping the job when the
apiserver patch fails. `isIdle` additionally treats a terminated
`poller` init container as proof of a claim, so a Pod running a job
survives even when the label never landed.

To replace a box, delete its Machine and follow the release:

```bash
kubectl -n <namespace> delete machine <machine-name>
kubectl -n <namespace> describe ovhdedicatedmachine <machine-name>
```

While the release waits, the `OVHDedicatedMachine` stays `Deleting` and
its `WaitingForRunnerJobs` event names the jobs still running. The wait
lasts as long as the node's longest in-flight job, up to six hours for a
Linux job, and has no deadline; deleting the Pods it names releases the
box sooner and kills those jobs. A terminating Pod on an unreachable Node
does not hold the release, so a dead box is released once its Pods are
evicted, about 5 minutes after the Node goes unreachable. The fleet then
runs one box short for the ~20-40 min reinstall and the self-join.

### Emergency SSH access

Every box carries the fleet key from `OVH_FLEET_SSH`, and the `ubuntu`
login has passwordless sudo after the self-join:

```bash
op read "op://tuist-k8s-<env>/OVH_FLEET_SSH/private-key" \
  --account=tuist.1password.com > /tmp/ovh-fleet
chmod 600 /tmp/ovh-fleet
ssh -i /tmp/ovh-fleet ubuntu@<box-ip>
# remember to: shred -u /tmp/ovh-fleet afterwards
```

Release reinstalls the box with the same key, so it stays valid across
re-adoption; the host key rotates.

## Token isolation (credential split, Linux pools)

Linux runner Pods run untrusted workflow code (incl. fork PRs), so
`podtemplate.Build` splits a Linux Pod into two containers running
the same runner image so the dispatch token never shares a
container with customer code:

- **`poller` init container** — the only container that mounts the
  audience-scoped projected token (`tuist-runner-token`). Runs
  `dispatch-poll.sh` with `TUIST_RUNNER_JIT_OUTPUT_PATH` set: it
  polls the dispatch endpoint, and on a claim writes the minted,
  job-scoped JIT to the shared `tuist-runner-jit` emptyDir, then
  exits 0. Runs as `runAsUser: 0` purely so it can write that
  root-owned emptyDir — it executes only our poll script, never
  customer code. Declared **after** the dind sidecar so it inherits
  the same `docker info` startupProbe gate the runner container had
  before the split.
- **`runner` main container** — holds no token. kubelet starts it
  only after the poller init container exits, so the JIT (if any)
  is already staged. Runs `run-job.sh`, which reads
  `TUIST_RUNNER_JIT_PATH` and execs the runner, or exits 0 when no
  JIT was staged (the 410 stale-image drain, or a poller abort).

Why this is enough: the token is pool-scoped and can claim a
pending `workflow_job` for the pool, so a Pod that leaks it could
race the warm pool for other tenants' jobs. The JIT is job-scoped
— it binds the runner to exactly one workflow run — so the runner
already operating under it loses nothing by holding it.

**Lifecycle consequence:** a warm-standby Linux Pod sits in
`Pending` (poller polling in Init) rather than `Running` until it
claims a job. `RunnerPoolReconciler`'s stale-Pending reap therefore
carries an `isIdle` guard so an image roll that races a claim
doesn't reap a just-claimed Pod that's momentarily Pending. The
`pod-lifecycle` billing reconciler keys on the `runner` container's
`terminated.finishedAt` (the poller/dind are init containers, absent
from `containerStatuses`), so billing still anchors on exactly the
customer job's runtime. macOS keeps the single-container shape (the
Tart VM is the isolation boundary; tart-kubelet projects the token
into it).

**Death-cause backstop:** the same reconciler also re-emits a
runner's final log on an abnormal end — a non-zero/SIGKILLed exit, or
a Pod reaped while still `Running` (the "lost communication" /
torn-down-microVM shape). It reads the `runner` container's tail via
`pods/log` and logs it to the controller's own (durable, long-lived)
stdout before the reap. Without this the trail (the `RUNNER_VITALS`
samples from `vitals.sh` + the streamed `_diag`) lives only in the
kubelet container log, which is GC'd the instant the Pod is deleted —
and `alloy` doesn't reliably win that race on a churning node, so
mid-job deaths otherwise leave nothing in Loki. A clean exit 0 (job
done, or no JIT claimed — and note a workflow that fails its own tests
still exits the runner 0) is skipped, so this fires only for runner
*infrastructure* deaths, not job outcomes.

**Rollout ordering:** ship the runner image carrying `run-job.sh`
+ the poller-mode `dispatch-poll.sh` (and pin
`runnersFleetLinux.pools[].runnerImage` to it) **before** the
controller that creates the split Pod shape. A new controller on an
old image would set `TUIST_RUNNER_JIT_OUTPUT_PATH` against a
dispatch-poll that ignores it and execs the job inside the poller
(token still mounted). The reverse (old controller, new image) is
safe: with the env unset the new script execs the runner in place —
a rollout bridge that can be dropped once every env runs the split
controller.

## dockerd sidecar (Linux pools)

Every Linux runner Pod gets a `dind` native sidecar (k8s ≥ 1.29:
initContainer with `restartPolicy: Always`) running the upstream
`docker:dind` image. The runner container stays unprivileged;
only the sidecar is `privileged: true`, bounded by the Pod's
`kata-qemu` microVM. **Linux pools must set `spec.runtimeClass:
kata-qemu`** — `podtemplate.Build` fails closed (returns an
error, controller logs it and creates no Pod) for a Linux pool
that would get the dind sidecar without it, so the privileged
container can't fall back to the host runc runtime and escape
the microVM boundary. The sidecar image (`runnersController.
dindImage`) is digest-pinned for the same reason: a privileged
container's exact bytes shouldn't move outside review.

Mirrors the ARC `gha-runner-scale-set` sidecar pattern. The
sidecar's `startupProbe` (`exec: docker info`) blocks the runner
container from starting until dockerd is reachable, replacing
what would otherwise be a polling loop on the runner side.
kubelet supervises dockerd — if it crashes, k8s restarts it.

Shape:

- `dind-sock` emptyDir at `/var/run` (both containers) exposes
  `/var/run/docker.sock`.
- `work` emptyDir at `/home/runner/work` (both containers) so
  `docker run -v $PWD:/x` paths resolve the same on either side.
  That path is the `work_folder` the server mints into the JIT
  config, **not** the runner's `<runner root>/_work` default —
  see "Why the work directory is /home/runner/work" below.
- `dind-externals` emptyDir at `/home/runner/actions-runner/externals`
  (sidecar only), filled by the `dind-externals` init container —
  the runner image running `cp -a` out of its own image layer into
  the volume, staged at `/mnt/dind-externals` there so the mount
  doesn't shadow the source. See "Why stage externals" below.
- `dind-storage` emptyDir at `/mnt/dind-disk` (sidecar only).
  Plain node-disk emptyDir — holds a sparse `disk.img` the
  sidecar entrypoint loop-mounts as ext4 onto `/var/lib/docker`
  before exec'ing dockerd. See "Why loop-mount" below.
- `DOCKER_HOST=unix:///var/run/docker.sock` injected into the
  runner so the docker CLI hits the sidecar.
- `--group=123` passed to dockerd so the socket GID matches the
  `docker` group baked into the runner image at build time.
- `--default-ulimit nofile=1048576:1048576` passed to dockerd
  so containers it spawns (incl. the buildkit container the
  `docker-container` buildx driver creates) inherit the high
  rlimit. Pair it with `ulimit -n 1048576` in the shell that
  starts dockerd to cover dockerd's own fd budget. Kata's
  microVM kernel defaults nofile=1024; without both, a docker
  build that walks a non-trivial `node_modules` tree EMFILEs.

### Why stage externals? (job `container:` support)

A workflow that declares `jobs.<id>.container` doesn't run its
steps in the runner container at all: the runner asks dockerd to
create a container and bind-mounts its own directories into it —
the work directory as `/__w`, then `_temp`, `_actions` and `_tool`
under it, `_temp/_github_home` as `/github/home`,
`_temp/_github_workflow` as `/github/workflow`, and `externals` as
`/__e`. Those source paths are resolved by **dockerd**, so they
have to exist in the sidecar's mount namespace, not the runner's,
and docker silently creates an empty directory for any that don't.

Everything but `externals` hangs off the work directory, which the
`work` volume shares with the sidecar. `externals` — the node
runtimes every JS action executes under — ships in the runner
image alone. Without the staged copy every step in the job
container dies on a missing `/__e/node2x/bin/node`.

Same fix ARC ships as `init-dind-externals`. The copy runs before
the sidecar, so it is in place by the time dockerd can serve a
container and a runner image that stops shipping externals fails
the Pod early rather than at job time. Cost is a per-Pod copy of
the node runtimes at warm-up, off the job's critical path.

### Why the work directory is /home/runner/work

`Tuist.Runners` mints the JIT config with an absolute
`work_folder` — `/home/runner/work` on Linux, `/Users/runner/work`
on macOS — to match GitHub-hosted's layout so on-disk artifacts
that bake absolute paths stay interchangeable between hosted and
self-hosted runs. The runner honors it and **never touches its own
`<runner root>/_work` default**.

So the `work` volume has to be mounted at `/home/runner/work`. Get
this wrong and nothing looks broken from the outside: normal jobs
keep passing, because the runner just writes to a container-local
directory instead of the shared volume. Only `container:` jobs
notice — dockerd bind-mounts a path that doesn't exist on its
side, docker creates it empty, and every step fails. `run:` steps
die first, on a missing `/__w/_temp/<id>.sh`; JS actions die on a
missing `/__w/_actions/<owner>/<repo>/<ref>/dist/index.js`.

Keep the two in sync: the podtemplate constant `workPath` and the
`work_folder` in `Tuist.Runners`. `TestBuild_LinuxDindSharesRunnerWorkDirectory`
pins the constant.

The PTY socket deliberately lives on its own `shell-sock` volume
rather than under the work directory: the runner hands the whole
work tree to a job container as `/__w`, and the runner container's
shell entry point has no business in there.

### Why loop-mount? (the virtio-fs / overlay2 gotcha)

Per upstream kata docs (`docs/how-to/how-to-run-docker-with-
kata.md`), **virtio-fs cannot serve as an overlayfs upper
layer**. overlayfs requires `trusted.overlay.*` xattrs on the
upper, and the host kernel CAP-gates `trusted.*` writes on
virtiofsd's effective uid no matter how virtiofsd is
configured (`--xattr` alone enables the xattr methods but
still hits EPERM on the trusted.* probe; `--xattrmap` is a C-
virtiofsd flag that Rust virtiofsd-rs doesn't accept and
breaks kata sandbox creation if passed). Dockerd silently
detects the failure and falls back to vfs; on vfs, BuildKit's
docker-container driver refuses overlayfs snapshotter and
uses runc-native, which fd-bombs heavy npm trees past any
sane rlimit.

Kata's two recommended workarounds are tmpfs `medium: Memory`
(eats pod RAM proportional to the image cache, and inode-
capped) or a loop-mounted disk image. We pick the loop-mount:
the sidecar entrypoint `truncate`s a sparse 100 GiB file on
the virtio-fs-backed `dind-storage` volume, `mkfs.ext4`s it,
mounts it `-o loop` onto `/var/lib/docker`. Dockerd then sees
a real kernel-native ext4 filesystem inside the kata VM, with
full `trusted.*` xattr support — overlay2 initializes
normally and BuildKit picks the overlayfs snapshotter. The
sparse file only consumes node-disk bytes as written (no pod-
memory tax), and the loop mount is bounded by the
`truncate -s` cap.

The entrypoint installs `e2fsprogs` via apk on each boot
because `docker:*-dind` doesn't ship `mkfs.ext4` by default;
worth baking into a custom dind image once the shape settles.
StartupProbe failureThreshold bumped from 30 → 60 to absorb
the ~8 s of pre-dockerd setup time.

The sidecar image is pinned via the chart's
`runnersController.dindImage` value and threaded into the
controller as `--dind-image`. Renovate keeps the pin bumped.

## Pool variants

Linux per-tenant slot sizes are now shape-keyed via Runner
Profiles. `runnersFleetLinux.shapes` in the chart values lists
the `(vcpus, memoryGb)` tuples the fleet exposes; the server
resolves a customer's `runs-on: tuist-<name>` to the matching
shape-keyed `RunnerPool` CR. Keep that list in sync with
`:runner_linux_shapes` in `server/config/config.exs` — same
catalog from two sides.

Follow-up: bake `e2fsprogs` into a custom `tuist-dind` image so
the `apk add` on every Pod startup goes away.

## Linux cache volumes

Local reflink image clones are implemented in
[`../runner-cache`](../runner-cache/AGENTS.md) and `cmd/cache-volumes`.
They share journal and object-storage publication with the macOS APFS backend. The agent image includes ext4/loop tooling, with no Ceph dependency.
See [host setup and rollout](cache-volumes.md).
RunnerPool `cacheVolumeRoot`/`cacheVolumeURL` enable UID-scoped host mounts in
runner and DinD, guarded by Kata. Prefer the storage-readiness node label without
requiring it: unavailable cache storage must not block ordinary Linux jobs. Incoming
mount propagation must work through Kata. Staging has verified GitHub native and
ordinary Docker jobs, Buildkite native commands, and GitLab shell jobs. Keep
the remaining operational validation limits explicit in the rollout guide.
Mount revision changes use the existing bounded idle rollout. No account-wide
cache root or infrastructure credential crosses into workflow containers.

Managed production enables custom volumes on normal deployment. The agent image
ships the bounded filesystem provisioning script, invoked by an opt-in privileged
init container in the host mount namespace. Existing/replacement nodes converge
before the agent can advertise readiness. Provisioning reserves 200 GB, retains
40 GB host headroom, and refuses nonempty paths, foreign mounts, symlinks, and
size changes. Controller and agent share a release version; the component release
tag is published only after both images exist.

- Cache volume action distribution and implemented Buildkite/GitLab adapters are
  documented in [cache-volume-integrations.md](cache-volume-integrations.md).
  Do not enable provider allocation by removing the GitHub filter alone; require
  verified provider/instance identity and publication policy first.

The real cache-filesystem CI job runs on `ubuntu-latest`, outside Kata's minimal
kernel, because the node agent is a host workload. Keep it a required image-build
dependency. Manual branch image builds publish only commit tags; `latest` is
reserved for main.

- Cache-enabled Linux pods run a descriptor-based mount broker in the existing privileged DinD sidecar. The runner and Docker job containers retain their existing privileges and separate PID namespaces; only their pod-scoped work socket and cache subtree are shared. Update the cache revision when changing this wiring and validate against the matching runner image.

Cache-agent metrics use a separate port 9091, annotated for Alloy discovery and
allowed only from the observability namespace. Keep acquisition on 8090 scoped
to runner pods. Low-cardinality phase/source/result counters and histograms cover
restoration, publication and bounded prefetch; never label metrics with lease IDs,
cache keys, paths or signed URLs. Non-production retains these metrics for recovery
drills. See `cache-volumes.md` for queries and rollout evidence.
The September 28 repeat-CI and recovery drill results are recorded in
`cache-volume-validation.md`; distinguish measured workload gains from prefetch
behavior that still needs production observation.
