# Thin storage handoff

This protocol complements CSI's conservative `ceiling-backed-v1` storage mode.
It does not enable physical overcommit or positive-fence serving. See
[storage qualification](../kura-volumes-csi/thin/validation.md) for the current
rollout decision and measured limits.

## Why connection retirement is insufficient

A Service update changes new connections. An existing connection can still
successfully write to the departing replica, then reconnect to the replacement
before asynchronous replication has copied that write. Staging observed two
fresh-write GET misses after successful PUTs even though the old connection
cohort had retired cleanly. A replication cursor also cannot prove retention:
ordinary backfill may advance past capacity- or age-rejected records.

The controller now persists the source process incarnation, destination pod UID,
destination process incarnation and peer URL before moving an endpoint. The
source checks the peer is a serving member of the same region. Through the
existing kubelet tunnel and end-to-end peer mTLS, the controller requests
`POST /_internal/migration/prepare`. The public router does not expose it.

Preparation checks the source's retained bodies and metadata on that exact
peer, using bounded batches and the existing content verifier. It pins and
checks the source feed to cover writes during the retained walk. It then arms a
write bridge before reporting ready. Every HTTP/gRPC mutation completion while
armed must verify the committed records on the named destination before it can
return success, including mutations admitted before arming. The protocol does
not copy through a new admission path or change eviction policy. Missing data,
lost feed history, an unavailable peer or changed identity fails closed.

Only the ready receipt permits `lvm-rebuild`. Primary selection pins the verified
destination; endpoint observation must name its exact pod UID. The existing peer
handoff, original connection-cohort retirement, donor deletion, replacement
catch-up and OnDelete/template safeguards still apply. Retirement closes HTTP/1
connections after their next response and sends HTTP/2 connections, gateway
gRPC included, a GOAWAY, so the cohort empties once in-flight streams finish
rather than at the five-minute connection age (unit-tested, not rehearsed on
staging). This is a planned legacy
cache migration protocol, not a new crash-consistency or global serving grant.

## Bounds, pauses and failures

Each preparation attempt has its own fixed 20-minute deadline; polling a running
attempt never extends it. A retained walk that cannot finish in one attempt
resumes: after every verified page the source keeps the index position it
reached and the feed position its pin started from, so writes the newest-first
walk already passed are proven from the feed. A later
`POST /_internal/migration/prepare` for the same source process and the same
destination `{url, incarnation}` after a failed attempt that advanced starts a
new attempt from that position. A failed attempt that advanced nothing (for
example, the destination lacks the record at the resume position) keeps
returning its failure instead of re-hashing the corpus. The failed attempt's
feed pin stays registered for the retry, bounded by the feed cap and the stale
consumer window, without holding up a drain. If the feed was trimmed past the
saved position, the retry walks from the top again. Reset, a rebind and a
different destination never inherit progress, and only a complete walk plus the
pinned-feed proof reports ready. This is unit-tested and has not been rehearsed
on staging. Verification uses batches of at
most 16 descriptors and existing 64 KiB hashing buffers. Destination verification
is serialized, but write acknowledgments group-commit: concurrent completions
queue on one gate, and a run that took its feed head after a write committed
proves that write, so waiters behind it return without another round trip. The
bridge loop still forces a full run every second to probe an idle destination.
Write acknowledgment waits at most five seconds. An unsuccessful
preparation disarms its bridge and leaves the controller unable to move routing.
Successful preparation cannot expire merely because the controller pauses: its
bridge stays active until the donor drains, retaining its feed pin with one
bounded background verification loop. The loop uses a weak runtime reference
and releases the pin on draining. Ordinary instances do not run this loop.
The source exports the bridge as `kura_migration_bridge_armed`,
`kura_migration_bridge_ready`, `kura_migration_bridge_last_proof_age_seconds`,
`kura_migration_preparation_walk_records` and the counters
`kura_migration_preparation_records_verified_total` and
`kura_migration_reproof_failures_total` (row "Storage migration bridge" on
`Tuist Kura / Details`). The proposed alert for a bridge armed but not ready for
15 minutes is described in `../helm/k8s-monitoring/alerts.md`.

Pausing source-node enrollment stops new storage moves, but cannot cancel a pod
or claim deletion already issued. Finish observation of that operation before
making changes to its source. Never remove the write binding or blindly restore
routing after `lvm-rebuild`; an armed bridge may already be protecting a moved
endpoint. A destination failure can refuse writes on the old source. Preserve
both volumes and investigate rather than treating readiness or a timeout as a
handover receipt. Changed process identities require fresh qualification; a
destination process restart is re-proved through the rebind below.

An armed source pays for replication and destination content verification before
acknowledging writes. The staging pause test deliberately kept routing on that
source: eight concurrent 4 MiB writes delivered only 16–21 MiB/s, with 2.10–3.12 s
p95, when every completion made its own destination round trip. Group commit
(2026-10-31) cuts sixteen concurrent completions to at most four round trips in
the unit test; the staging measurement has not been repeated. Ordinary unarmed
serving does not perform these checks. Keep this temporary
cost in the rollout budget, observe write latency during each handoff, and do not
pause a ready bridge indefinitely as a substitute for completing the move. An
unacceptable latency increase should stop selection of further nodes while the
already armed handoff is completed or recovered using its verified identities.

A failed **unarmed preparation** can be retried without restarting the writer:

1. Clear the selected node's `tuist.dev/kura-lvm-migrate` annotation. Retain its
   cordon and verify no deletion has been issued and the source pod has no
   `kura.tuist.dev/lvm-rebuild` annotation.
2. Correct the preparation failure and record the source's current
   `connection_incarnation` and exact target from its
   `kura.tuist.dev/lvm-write-target` annotation.
3. Through the same authenticated peer connection, send
   `POST /_internal/migration/reset` with the same `{incarnation, target}` JSON
   used for preparation. It serializes against acknowledgments and only clears
   a completed failed preparation, including its saved walk progress and feed
   pin. A running preparation, ready/armed bridge, wrong source process or wrong
   destination returns conflict. No keys or data are deleted. An already empty
   state is idempotent.
4. After a successful reset, remove only that source pod's write-target
   annotation using a resource-version-guarded update. Recheck identities,
   destination capacity and catch-up, then reselect the source node. This creates
   a new bounded preparation; polling the old attempt never extends its deadline.

An armed handoff has no reset shortcut. Preserve the destination and donor and
complete or explicitly recover the handoff; clearing the bridge would reintroduce
the successful-PUT/missing-GET race.

### Abort before demotion

`POST /_internal/migration/abort` (internal peer mTLS only) takes the same
`{incarnation, target}` body as prepare and reset and answers
`{"incarnation": "<source connection_incarnation>", "aborted": true}`. It
clears the migration for exactly that target whatever its state (running,
failed, ready or armed):

- the bridge is disarmed first, so acknowledgments already waiting on it
  complete as ordinary asynchronous writes instead of failing;
- it then serializes with acknowledgments through the same gate, discards the
  saved walk progress and releases the feed pin;
- a running preparation, the bridge loop and a re-proof notice the migration
  is gone and exit without writing state back; a later prepare walks from the
  first record.

With nothing active it is idempotent (200). A wrong source incarnation or a
different target that owns the migration returns 409.

It is safe only while the source was never demoted (no
`kura.tuist.dev/lvm-rebuild` annotation): routing never moved through the
migration, and disarming returns the source to the ordinary asynchronous
replication it served with before preparation. The runtime cannot check that
precondition; the caller must. Abort is unit-tested and has not been rehearsed
on staging.

### Destination process restart

When the destination pod keeps its UID and URL but reports a new
`connection_incarnation`, the controller sends
`POST /_internal/migration/rebind` with `{incarnation, target, replacement}`,
where `replacement` is the same URL with the new process incarnation. Only an
armed bridge accepts it; a repeated request for the current replacement is
idempotent. The source then:

- keeps the bridge armed, so writes still return success only after their
  records verify on the destination, now the new process;
- clears its proof and re-walks every retained record plus its pinned feed on
  the new process, retrying until that succeeds or the source drains;
- reports `ready` again only after that re-proof completes.

The controller records the new incarnation in the write-target annotation only
after the source accepts the rebind, and does not mark or retire the donor
until preparation reports ready again. A record the restarted process lost
keeps the bridge unready rather than moving routing past it. A replaced pod
(new UID), a restarted source or a disarmed preparation is not rebound and
still fails closed.

### Single-copy instances

A single-replica instance has no sibling to take its endpoint, so once its
source node is selected the controller runs a temporary second ordinal. The
declared spec keeps one replica; the pods, roles, disruption budget and storage
lifecycle count two while the migration runs.

1. The StatefulSet scales to two. Ordinal 1 lands on the declared storage on a
   prepared node and is recorded as the standby by
   `kura.tuist.dev/lvm-migration-standby` on its claim.
2. Once the standby has completed initial backfill, ordinal 0 hands its
   endpoint to it through the ordinary handoff above and is rebuilt.
3. Once the rebuilt ordinal 0 has completed initial backfill, the standby hands
   the endpoint back the same way, including the write bridge on thin storage.
4. The standby claim is released and the StatefulSet scales back to one.

A retained claim on other storage at ordinal 1, left by an earlier scale-down,
is never adopted; the migration holds until it is removed. Clearing the source
selection after step 1 pauses the move with the standby still running; it is
released only after ordinal 0 has moved. A single-host region has no landing
node and still needs another host.

## Qualification

Keep equal runtime resources and storage sizes in layout comparisons. A
successful handoff test is not a raw-I/O no-regression result. The staging probe
has no application retry loop; Go's transport may retry an idempotent request on
a stale connection. It journals hashes for every successful write, then verifies
the full journal with its expected count against the Service and each replica.
Also verify the pre-seeded corpus, stable PVC identity during template restart,
physical allocation, reserves and unrelated workload identities. Package/runtime
changes require the Linux test gate and another staging qualification before
production enrollment.
