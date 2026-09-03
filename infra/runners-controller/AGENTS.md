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
  `maxReplicas`, `scaleDownCooldownSeconds`) live in the
  `RunnerPool` spec, so a tuning change is helm-only.

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
    shape plus the kata RuntimeClass's 2.5 GiB podFixed), a third of an
    AX162-R and over half of the OVH RISE-L the fleet is moving to, so
    it needs a contiguous block that 8 and 16 GiB Pods keep carving up.
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
    (2m), the RunnerPool reconciler taints one eligible host
    `tuist.dev/reserved-for=<pool>:NoSchedule`. Every runner Pod
    tolerates that key at its OWN pool's value, so the host stops
    admitting everyone else while its seats accumulate. Running jobs are
    waited out, never evicted; only idle Pods of other pools are
    retired. The taint is removed when the Pod lands or after
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

  Only nodes that report `Ready=True`, remain schedulable, and have no
  memory, disk, or process identifier pressure contribute to either
  budget. A fleet filtered to zero capacity still takes the existing
  per-pool fallback, so a transient node roll never triggers a mass
  scale-down of warm Pods. Pod creation has a separate fail-closed
  healthy-node gate described below.

  The reconciler reads nodes via the cluster-scoped `nodes` verb in
  the ClusterRole. Fleet-capacity, pool-list, and sibling-signal
  failures fall back to the per-pool target — a transient read blip
  must never trigger a mass scale-down or block independent scale-up.
  A pool with an unrecognised `OS` (or without autoscaling enabled)
  skips the allocator entirely.

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
  `spec.provisioning.maxConcurrentPerFleetSelector` (default 4), using
  the lowest sibling value so one mismatched pool cannot weaken the
  fleet boundary. Excess demand remains a replica gap and is retried
  every five seconds. macOS pools skip this gate.

  The count deliberately includes Pods with no node. An unbound Pod is
  one the scheduler may bind at any moment, and nothing re-checks
  admission between that bind and the sandbox start, so discounting
  unbound Pods would let a backlog build and then start all at once when
  capacity returns — the very burst the ceiling exists to prevent.
  Scheduling gates do not help here either: a gate can be removed but
  never re-added, so a Pod that turns out to be unschedulable after
  ungating is back to holding a slot with no way to reclaim it.

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
  `tuist_runners_pool_pod_start_timeouts_total{pool,reason}`,
  and `tuist_runners_pool_stuck_terminations_total{pool}`. The last one
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

  Pod-level autoscaling only — bare-metal Host count is operator-
  managed via the CAPI cluster topology, since Hetzner Robot hosts
  are monthly-billed and can't be auto-ordered. To grow capacity,
  the operator orders another `tuist-bm-<env>-*` host in the Robot
  panel and bumps the cluster topology's `runners-linux` MD
  replicas; the `hetzner-robot-controller` reflects the new server
  into a `HetznerBareMetalHost` CR automatically.

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

## Linux runner substrate: Hetzner Robot bare-metal hosts (caph)

Linux runner Pods run as Firecracker microVMs (via Kata Containers)
on Hetzner Robot dedicated servers (AX42-U class for staging,
AX162-R for production). Two cooperating mgmt-cluster components
drive adoption end-to-end:

* **caph** (upstream CAPI provider) claims `HetznerBareMetalHost`
  CRs, drives Robot rescue, runs `installimage`, and waits for
  kubeadm-join.
* **`hetzner-robot-controller`** (Tuist-built, see
  [infra/hetzner-robot-controller/](../hetzner-robot-controller/AGENTS.md))
  fills the gap caph leaves: reflects Robot's server inventory
  into `HetznerBareMetalHost` CRs (so caph has something to claim)
  and auto-fills disk WWNs once caph populates `hardwareDetails`.

Operator workflow becomes Scaleway-shaped:

```
operator orders AX42-U via Robot panel, sets name `tuist-bm-<env>-<n>`
        │
        ▼
hetzner-robot-controller polls Robot, sees the new server, creates
a HetznerBareMetalHost CR labeled
`app.kubernetes.io/managed-by=hetzner-robot-controller`
        │
        ▼
HetznerBareMetalMachineTemplate's `hostSelector` matches that
label; caph claims the new CR
        │
        │ (caph reads Robot credentials from `org-tuist/hetzner`
        │  Secret, contacts Robot API to reboot into rescue mode)
        ▼
Box boots Hetzner rescue; caph SSHes in via `hetzner-bare-metal-ssh-key`,
reads hardware details, writes them to `spec.status.hardwareDetails`
        │
        ▼
hetzner-robot-controller watches the CR, sees populated
hardwareDetails + empty rootDeviceHints, patches RAID 1 WWNs from
the first two disks into `spec.rootDeviceHints.raid.wwn`
        │
        ▼
caph runs `installimage` (Ubuntu 24.04 LTS on RAID 1 across both NVMes)
        │
        ▼
Box reboots into the installed OS; cloud-init runs the bare-metal
worker `KubeadmConfigTemplate` (containerd + kubeadm + `kubeadm join`)
        │
        ▼
Node registers in workload cluster, labeled
`node.cluster.x-k8s.io/pool=runners-linux` and
`tuist.dev/kata-runtime=true`
        │
        │ (kata-deploy DaemonSet sees the kata-runtime label, installs
        │  Kata Containers + Firecracker binaries, configures
        │  containerd, restarts containerd)
        ▼
Node ready to schedule runner Pods (which carry
`runtimeClassName: kata-fc`, so each Pod becomes a microVM)
```

No hand-authored `HetznerBareMetalHost` CR, no manual WWN copy.

### Fleet credentials

Robot user/pass and the shared SSH key are fleet-level — one
Hetzner Robot account spans every AX-class host across staging /
canary / production — so both 1P items live in the mgmt
cluster's own vault (`tuist-k8s-mgmt`).

The mgmt cluster doesn't yet have external-secrets-operator
installed (that's part of the workload-side platform chart), so
the operator creates the two Secrets manually once per mgmt
cluster bring-up:

```bash
# Robot webservice credentials — caph drives the Robot API with these
op read "op://tuist-k8s-mgmt/HETZNER_WEBSERVICE/username" > /tmp/robot-user
op read "op://tuist-k8s-mgmt/HETZNER_WEBSERVICE/password" > /tmp/robot-pass
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist create secret generic \
  hetzner-robot-credentials \
  --from-file=hetznerRobotUser=/tmp/robot-user \
  --from-file=hetznerRobotPassword=/tmp/robot-pass
# caph reads Robot keys from the SAME Secret as the hcloud token
# (the one named in HetznerClusterTemplate.hetznerSecretRef, today
# `hetzner`). Merge the keys in:
ROBOT_USER_B64=$(base64 -w0 < /tmp/robot-user)
ROBOT_PASS_B64=$(base64 -w0 < /tmp/robot-pass)
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist patch secret hetzner \
  --type=merge -p "{\"data\":{\"hetznerRobotUser\":\"${ROBOT_USER_B64}\",\"hetznerRobotPassword\":\"${ROBOT_PASS_B64}\"}}"
shred -u /tmp/robot-user /tmp/robot-pass

# SSH key — caph SSHes into rescue mode with this
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/public-key-name" > /tmp/sshname
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/public-key"      > /tmp/sshpub
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/private-key"     > /tmp/sshpriv
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist create secret generic \
  hetzner-bare-metal-ssh-key \
  --from-file=sshkey-name=/tmp/sshname \
  --from-file=ssh-publickey=/tmp/sshpub \
  --from-file=ssh-privatekey=/tmp/sshpriv
shred -u /tmp/sshname /tmp/sshpub /tmp/sshpriv
```

Once ESO lands on the mgmt cluster, both Secrets can move to
`ExternalSecret` resources in `bare-metal-staging.yaml` and this
manual step goes away.

### Bringing up a new bare-metal host (operator workflow)

1. **Order an AX-class server from [robot.hetzner.com](https://robot.hetzner.com)**.
   FSN1 for staging (matches the Cloud cluster region). Paste the
   shared SSH public key from `tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY`
   into the order form. **Important**: set the server **Name** in
   the Robot panel to `tuist-bm-<env>-<n>` (e.g.
   `tuist-bm-staging-3`) — that's what `hetzner-robot-controller`
   matches on. Wait for the fulfillment email.

2. **Bump `runnersFleetLinux.pools[].autoscaling.maxReplicas`** (and
   `minWarmPoolFloor` if you want it always-hot) in
   `values-managed-staging.yaml` to match the new total host count
   × per-host microVM density. The runners-controller autoscaler on
   the workload cluster patches the `runners-linux` MD's replicas
   on the mgmt cluster to match. Push.

That's it. From the operator's point of view the only manual gate
is the Robot order itself; everything from "controller spots the
new server" through "Node is Ready with kata-deploy installed"
runs unattended.

To **watch** progress on the mgmt cluster while it happens:

```bash
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist \
  get hetznerbaremetalhost -w
```

Status goes through `(empty)` → `preparing` → `registering` →
`image-installing` → `ensure-provisioned` → `provisioned` →
`kubeadm-joined`. ~8-15 min total for an AX42-U.

To **verify the Node** registered in the workload cluster:

```bash
kubectl --kubeconfig "$STAGING_KUBECONFIG" get nodes \
  -l node.cluster.x-k8s.io/pool=runners-linux
```

The kata-deploy DaemonSet auto-installs (it watches for
`tuist.dev/kata-runtime=true`). Wait for it to mark the node
`katacontainers.io/kata-runtime=true` before runner Pods will
schedule:

```bash
kubectl --kubeconfig "$STAGING_KUBECONFIG" -n tuist-staging \
  get pods -l app.kubernetes.io/name=kata-deploy
```

### cgroup leak on kata nodes (fixed for new hosts; existing hosts need action)

Until 2026-08-13 the `kata-qemu` containerd handler ran with
`SystemdCgroup = false` while kubelet ran `cgroupDriver: systemd`. The
`sed` in `bare-metal.yaml` that flips the runc handler to `true` only
rewrites what `containerd config default` emitted, and the kata block is
appended after it, so kata silently kept the default.

Under that mismatch the kata shim writes the systemd slice name kubelet
hands it as a literal directory at the cgroup root
(`/sys/fs/cgroup/kubepods-burstable-pod<uid>.slice:cri-containerd:<id>`)
instead of nesting it under `kubepods.slice`. Nothing owns those: systemd
never knew about them, the shim does not remove them, and they accumulate
one per container start forever. Exhaustion makes every later cgroup
`mkdir` return ENOSPC — the node keeps reporting `Ready` while failing
every new Pod sandbox. Measured at ~65k leaked root cgroups (~130k total
descendants) on both 85-day nodes versus 70 on a freshly rebooted one,
growing ~2/min under load.

`bare-metal.yaml` now sets `SystemdCgroup = true` on the kata handler,
so **newly provisioned hosts are clean**. Existing hosts are a different
story, and the reason is worth stating precisely, because "the manifest
is applied automatically" is true and still does not help.

`mgmt-cluster-apply.yml` applies `bare-metal*.yaml` on every push that
touches `infra/k8s/clusters/**`, falling back to delete + apply because
`HetznerBareMetalMachineTemplate.spec` is immutable, and then asserts no
drift. So the template in the cluster does match Git. But the template
is a blueprint consumed at Machine creation: `postInstallScript` runs
once, inside Hetzner `installimage`, and is not a reconciliation loop
over a live host's filesystem. CAPI propagates a template change by
*replacing* Machines, not by mutating them.

That replacement is currently wedged, and has been since 2026-06-17.
`tuist-runners-linux-pvv5b` reports `UP-TO-DATE: 1` of 2 ready Machines
and sits in `ScalingDown` with a third Machine stuck `Provisioning`,
whose condition reads `no available host (all hosts are in use - found
4 hosts)`. The MachineDeployment has no explicit `spec.strategy`, so it
takes the CAPI default of `maxSurge: 1, maxUnavailable: 0` — create the
replacement first, then delete the old Machine. On a bare-metal pool
where every `HetznerBareMetalHost` is already claimed there is no host
to surge onto, so the roll can never start.

The consequence: a `bare-metal.yaml` change does not reach existing
hosts, not because drift goes unnoticed but because the rollout that
would deliver it cannot make progress. Options are to give the pool a
spare host, or to set `maxSurge: 0` + `maxUnavailable: 1` so a Machine
is deleted first and its freed host reprovisioned. The second costs one
node of capacity per roll, which on a two-node fleet is the same
exposure as the manual path below.

Check a host without SSH — the count should be in the hundreds, not
thousands:

```bash
kubectl get --raw "/api/v1/nodes/<node>/proxy/metrics" | grep node_cgroups_cgroups
```

Remediation splits into two independent halves: **stop the leak**
(config) and **reclaim what already leaked** (sweep). Only the first
needs a containerd restart.

**Stop the leak.** Edit `/etc/containerd/config.toml` to add
`SystemdCgroup = true` under
`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata-qemu.options]`,
then restart containerd. Cordon and drain first: restarting containerd
bounces every sandbox on the box, including Cilium. Do one host at a
time — the Linux fleet is two nodes and a single node saturates at ~99%
memory, so taking both out at once is a full outage rather than degraded
capacity.

**Reclaim the leaked cgroups — in place, no reboot.** The leaked
directories are flat leaves: no child cgroups, no processes, owned by
nothing. `rmdir` removes them and the kernel reclaims the underlying
cgroup objects roughly 1:1, asynchronously (`/proc/cgroups` trails the
directory count by a few seconds, so re-read it after a pause rather
than concluding the removal did nothing).

**There are two leaked populations, not one, and they are the same
size.** Sweeping only the first leaves the node at half its leak and
looks like the reclaim failed:

- `/sys/fs/cgroup/*:cri-containerd:*` — the literal slice names at the
  cgroup root, described above.
- `/sys/fs/cgroup/kata_overhead/*` — one per sandbox, named by
  container ID. Same shape (flat empty leaves), same one-per-container
  -start growth, never reclaimed.

On the wedged production host these were 65478 and 65486 respectively.
Sweeping only the root population dropped `/proc/cgroups` memory from
131134 to 65710 and no further, which reads as a stuck reclaim; it was
`kata_overhead` still holding the other half. Sweeping both took it to
250.

Whether `SystemdCgroup = true` also stops the `kata_overhead` leak is
**not established**. The root-level leak is explained by the cgroup
driver mismatch; the overhead cgroups are created by the shim either
way, and only a host running the fixed config can settle it. Check
`kata_overhead` growth specifically on the first newly provisioned
host. The alert covers this either way — it counts cgroups, not
directory names, which is why it was set against normal (hundreds)
rather than against a known pattern.

The sweep is safe by construction and needs no drain. For the root
population the path is itself the guard: a correctly-nested cgroup
lives under `kubepods.slice`, so anything matching
`*:cri-containerd:*` at the cgroup *root* is by definition leaked.
Under `kata_overhead` every child is a candidate. In both cases
skipping a non-empty `cgroup.procs` leaves live sandboxes untouched —
measured as `kept_busy` equal to the number of running containers — and
an in-use cgroup would fail `EBUSY` anyway.

**Verify with the directory count, not `/proc/cgroups`.** Directory
counts drop immediately and deterministically. `/proc/cgroups` lags by
tens of seconds and keeps counting cgroups whose directory is gone but
whose charges are not yet reclaimed, so a clean host can read 1500
there while holding 65 directories.

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

**A fully wedged node cannot be swept this way**, and this is the
important limitation. Creating the debug Pod is itself a Pod creation,
so it fails with the same error the node is failing everything else
with:

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
failing loudly, and a shell loop forks `rmdir` once per directory.
Count with `ls | grep -c ':cri-containerd:'` instead.

Measured on both production hosts and staging/canary (2026-08-13):

| host | state | root leaked | `kata_overhead` | memcg before → after |
| --- | --- | --- | --- | --- |
| prod `vl8jt` | wedged, ENOSPC | 65478 | 65489 | 131134 → 250 |
| prod `bkzxh` | rebooted 08-13, re-leaking | 14 | 322 | 621 → 287 |
| staging | 85-day | 3359 | 3359 | 8338 → 1552 |
| canary | 85-day | 2855 | 2855 | 7208 → 1509 |

Zero failures anywhere. Every node stayed `Ready` with no pressure
condition and its running Pods were unaffected. The wedged host went
from every Pod `Pending` to 16 `Running` within a minute of the sweep,
without a reboot.

So the Hetzner Robot hardware reset is avoidable even on a wedged
host — but only over SSH. The reboot only ever mattered as a blunt way
to clear the cgroup tree, and the sweep does that while the node keeps
serving.

`node_cgroups_cgroups{subsys_name="memory"}` is alerted on at 20000; see
"Node leaking cgroups" in `infra/helm/k8s-monitoring/alerts.md`.

### Replacing a node without killing CI jobs

Every Machine replacement — a template roll, a MachineHealthCheck
remediation, a scale-down — drains the node first, and Cluster API's
default drain *evicts* Pods. On a runner node that means killing
customer CI jobs mid-flight, which surfaces as "lost communication".
There is no PodDisruptionBudget in `tuist-runners`, so nothing held
that back.

Two pieces make a replacement safe, and neither works without the
other:

1. **`MachineDrainRule`** (`infra/k8s/clusters/machinedrainrules.yaml`)
   sets `behavior: WaitCompleted` for Pods labeled
   `tuist.dev/runner=true`. Cluster API stops evicting them and waits
   for a terminal phase instead. Runner Pods are single-shot
   (`RestartPolicy: Never`, one `workflow_job`, then exit), so a Pod
   running a job completes on its own and releases the drain.
2. **The idle reap** (`controllers/node_drain.go`) retires idle Pods on
   a cordoned node. Without it the drain never converges: an idle Pod
   is a dispatch poller with nothing to finish, so `WaitCompleted`
   would wait on it forever, and the cordon stops new Pods landing
   without removing the ones already bound. Idle Pods are pure warm
   capacity, so retiring them costs only a cold start and the
   autoscaler replaces them on a node that can still accept Pods.

The reap reads `isIdle`, **not** the `tuist.dev/runner-pool-owner`
label. This is also why a PodDisruptionBudget cannot do this job: a PDB
selects on labels, and that label is best-effort — the server degrades
to running a job without it rather than dropping the job when the
apiserver patch fails. `isIdle` additionally treats a terminated
`poller` init container as proof of a claim, so a Pod running a job
survives even when the label never landed.

Consequences worth knowing before triggering a roll:

- A drain takes as long as the node's longest in-flight job — up to six
  hours for a Linux job. `nodeDrainTimeoutSeconds: 0` on the
  `bare-metal-worker` class leaves that unbounded on purpose: any finite
  value is a promise to kill a job once exceeded.
- **Budget a day for a full roll, not a quarter hour.** With
  `maxSurge: 0` / `maxUnavailable: 1` the pool runs one node short for
  the whole replacement, and that is dominated by the drain rather than
  by the ~8-15 min `installimage` cycle. Two hosts replaced
  sequentially is roughly 13 hours of halved capacity. On the
  single-host staging and canary pools it is a full outage of Linux
  runners for the same window.
- That trade is deliberate: the Linux pools carry internal workflows
  only. A spare host is the alternative — it restores `maxSurge: 1` and
  removes the dip entirely, because the replacement builds while the
  old node drains — and is what to revisit if customer workloads ever
  land on Linux.
- The stall risk is covered by alerting, not by a cap: "Worker node
  pool stuck mid-rollout" in `infra/helm/k8s-monitoring/alerts.md`
  fires on `upToDateReplicas < spec.replicas` after 24 hours, which is
  set to clear that worst-case healthy roll rather than to catch a
  wedge quickly.

### Emergency SSH access

If a bare-metal host misbehaves and caph isn't responding, the
operator can SSH in directly using the shared key from
`tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY`:

```bash
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/private-key" \
  --account=tuist.1password.com > /tmp/hbm
chmod 600 /tmp/hbm
ssh -i /tmp/hbm root@<host-ip>
# remember to: shred -u /tmp/hbm afterwards
```

The key remains valid through reinstalls because caph configures it
into `/root/.ssh/authorized_keys` as part of the cloud-init
bootstrap.

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
