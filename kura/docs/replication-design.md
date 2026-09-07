# Kura Replication Design

Status: proposed. Not implemented, not scheduled.

This document is the design only. The analysis behind it — why the current
mechanism does not scale, what else was considered, the options deliberately
left out — lives in [`replication-scaling.md`](replication-scaling.md).

Two orthogonal axes run through everything below. **Which link** — the
intra-region *replica* link or the inter-region *region* link — decides the
guarantee and the cost. **Which direction** — *sync backward* from newest toward
oldest, *sync forward* from a position toward newest — decides how a node reads
its peer. Both links pull, and both long-poll.

| | **replica** (intra-region) | **region** (inter-region) |
| --- | --- | --- |
| **sync backward** — newest → oldest | `version_ms` index, horizon-bounded; on cold start or restart | `version_ms` index, horizon-bounded; on a gateway entering or leaving the mesh |
| **sync forward** — position → newest | bounded arrival feed, cursor, commit-ordered | `version_ms` index ascending from the region watermark |

---

## 1. Requirements

The two links have different jobs, and conflating them is what made earlier
drafts complicated. Stated separately:

| | **replica sync** (intra-region) | **region sync** (inter-region) |
| --- | --- | --- |
| Latency | fast — a rollout must not cost cache hits | slower is fine |
| Completeness | **no records lost**, especially recently written ones | best effort; missing records in edge cases is acceptable |
| Cost | loopback, effectively free | metered WAN |
| Peers | the sibling | one gateway per remote region |

Everything below follows from that split. The strict guarantee is bought where
it is cheap; the loose one is accepted where it is expensive.

---

## 2. Topology: one gateway per region

> Each region designates a gateway. Gateways exchange entries with each other.
> A gateway exchanges entries with the non-gateways of its own region. A region
> has at least one gateway, normally exactly one. "Exchange" means both sides
> pull.

WAN cost becomes `(R-1) x S` by construction rather than `(N-1) x S`: bytes
cross a region boundary once and spread over loopback inside it. Roles also make
cross-region egress attributable — it is the gateway's — without the shaping
needing to know about them: per-tenant shaping stays per-pod and role-agnostic,
both replicas carry the class sized for the gateway's cross-region share, and
the non-gateway's unused headroom is borrowed under HTB. The role can move
without anything being re-rendered, so there is no server-to-controller
feedback path to build.

**Bidirectionality inside the region is load-bearing**, not symmetry for its own
sake: the gateway pulling *from* its non-gateways is the only way data written
on a non-gateway leaves the region. During a rollout both replicas take writes
for the drain overlap, so neither is a superset of the other and the link has to
work both ways.

Non-gateways pull only from their own gateway; they never open a cross-region
link. A region's cross-region path is its gateway, and when that path is broken
the answer is to re-designate (§2.2), not to let other nodes route around it.

### 2.1 The gateway is the complement of the primary

Do not create a second designation. The gateway is derived from the one that
already exists:

- **Two replicas** — the gateway is the Ready, non-draining replica that is
  *not* the primary. Cross-region work then lands off the node serving clients,
  which is the point of having a standby at all.
- **One replica** — that instance is both primary and gateway.
- **No eligible non-serving replica** — the primary takes the role rather than
  the region losing it.

**Two replicas per region is an assumption, not a coincidence**, and the
complement rule needs no tie-break because of it. A third replica would share
the same host, so it multiplies storage cost without adding failure
independence; read scaling does not motivate one either, since a single primary
serves. If that ever changes, the tie-break is lowest ordinal among the eligible.

The Ready-and-non-draining qualifier is load-bearing. A bare complement rule
hands the gateway to the pod on its way out the moment the primary drains and
serving flips, which is exactly what INV-5 forbids.

**Who decides, and who tells the instances, are different questions.** The
kura-controller knows the Kubernetes facts — `choosePrimaryPod` supplies the
primary designation, already sticky
(`if current != "" && routable[current] { return current }`), non-reverting,
gated on the standby being caught up (`primaryPodHealthFromSamples`), with a
lowest-ordinal tie-break and an ordered handover (`demoteEvacuatingPods` runs
before the Services reconcile). Deriving the gateway from it costs no new
controller state and stops the two roles developing contradictory hysteresis.

But the controller cannot reach self-hosted instances, so it cannot be the
distribution path. **The server is the authority instances consume.** The
controller publishes what it knows (primary, rollout state) into the
`KuraInstance` status the server already reads; the server resolves the roles
and hands them to every node — managed and self-hosted alike — in the peer list
they already fetch (`TuistWeb.Internal.KuraMeshController`, and the read-only
`KURA_MESH_PEERS_SYNC` view for managed pods).

The invariant that makes this work: **a node learns its own role, and every
peer's, from exactly one place — the peer list.** It never infers it from
Kubernetes, from its ordinal, or from observing traffic. The controller may
label pods for its own purposes, but a label is not a designation.

**Role churn is free here, which is why the derivation is affordable.** Across a
deploy the role can move up to four times — the gateway rolls, the primary takes
it, the gateway returns, the primary drains and hands it back. That would have
been expensive when a peer's position was a per-source sequence cursor. With a
`version_ms` watermark held as region state (§4.3), a newly designated gateway
already has the region's current position, so a change costs nothing but a brief
pause in the cross-region pull.

### 2.1.1 Suspend the role during a rollout

Better than absorbing that churn is not to have it. The server runs the
rollout and publishes the roles, so it can **suspend a region's gateway role
for the duration of that region's rollout and designate once when the rollout
reaches a terminal state**. The controller only reports rollout state; the
suspension, its expiry and the re-designation all live on the server, which is
also what keeps them working when the controller itself is what wedged.

"Terminal" must include **failed**. A rollout that errors out must still get a
gateway assigned, or the region is left indefinitely out of sync — the failure
mode that matters most, because a failed rollout is precisely when nobody is
watching the replication topology.

While suspended the region does no cross-region sync at all. That is acceptable:
inter-region convergence is explicitly allowed to lag, and a deploy is minutes.
In exchange, no role moves mid-rollout and no pod is designated while draining.
Nothing is missed by the pause: the region's watermarks froze when the pull
stopped, so the first pass after re-enabling starts from before the suspension
and lists everything since. The pass-start buffer (§4.4) covers only what was
in flight when the watermarks froze, as it does for any pass.

**The suspension must expire.** A rollout that wedges — and they do — would
otherwise stop cross-region replication for that region indefinitely and
silently. The server restores the role after **30 minutes** regardless of
rollout state. Restoring early is safe, because the designation rules still
apply to whatever the rollout left behind — Ready, non-draining, never a pod
about to be drained — so an expired suspension costs at most the churn the
suspension was meant to avoid. Alert on the expiry firing, not on the
suspension itself.

**At most one region per mesh is suspended at a time.** A second region that
starts rolling while one is suspended keeps its gateway and absorbs the churn
the way §2.1 describes — role changes are cheap, so this needs no cap
mechanism, and it guarantees that cross-region sync never pauses mesh-wide.

### 2.2 What the server publishes, and what makes it re-designate

Annotate the peer list in the existing mesh view — `{url, region, gateway}` per
entry, not a bare boolean. A scalar tells a node its own role but not which peer
is its region's gateway or which remote peers are gateways, both of which it
needs in order to know who to pull from. One document then lets every node
derive the whole topology, which also makes it observable and testable.

Rules the server holds to:

- Never publish zero gateways for a region that has a Ready node — except
  transiently while the holder restarts, or while a rollout suspension is in
  force (§2.1.1).
- Prefer overlap to a gap when moving it: two gateways for a transition window
  cost one duplicate fetch and self-correct; zero stalls the region.
- Never designate a pod that is about to be drained; the role would evaporate
  seconds later.

Readiness alone is not a sufficient health signal for this role. A gateway can
stay Ready and heartbeating while its cross-region path is broken — control
plane fine, WAN stuck — and nothing would ever fire. So the gateway reports, in
the mesh heartbeat it already sends, **the time since its last successful
forward read from each remote region** together with the watermark itself. The
signal is deliberately *not* the watermark's age: an idle remote region writes
nothing, so its watermark ages without anything being wrong, whereas an empty
long-poll that returns cleanly still proves the path is alive.

The server re-designates when a gateway's last successful read is older than
**5 minutes against every remote region** — the signature of a node whose
cross-region path is broken. A single stale pair is the path between two
regions, and moving either role cannot fix a path: it raises an alert and
leaves the topology alone. After any re-designation the region is left alone
for **15 minutes**, so a failure the new gateway shares with the old one
cannot flap the role. That keeps the decision with the authority, which is why
nodes need no bypass rule of their own: a node only ever talks to the peers
its role says it talks to, and a stuck path is fixed by moving the role rather
than by routing around it.

### 2.3 A co-located instance is its own region

The Kura instance co-located with the runners is **its own region of one**: both
primary and gateway, by the one-replica case above. Nothing special is needed —
the server publishes it in the peer list like any other region, and it
participates in the gateway clique.

This is also where placement decides the bill. Its cross-region egress is
`(R-1) x S` as a region of one. If it were instead placed *inside* an existing
region, behind that region's gateway, the write-hot node's cross-region egress
would be zero: it writes locally, the gateway pulls over the local hop and pays
the WAN. Worth knowing, even where the physical topology does not allow it.

### 2.4 Self-hosted deployments

Two shapes, and they degrade differently.

**Enrolled self-hosted nodes** — those that talk to the server — need no special
handling. They fetch the same peer list over the mesh heartbeat and read their
role from it exactly as a managed pod does. The controller is absent, so the
server resolves roles from what it can see (registered endpoints, their reported
`traffic_state`, their liveness) rather than from a `KuraInstance` status.

**Fully self-hosted meshes with no server** have no authority at all, so each
instance acts as its own, from the same inputs every node already has:

- **Region.** `KURA_REGION` is already required configuration. Each node
  reports it in `/_internal/status`, and the existing peer health probe reads
  it for every peer it already polls. A peer that reports no region — an older
  build — is treated as a region of one.
- **Membership and Ready.** Static `KURA_PEERS` plus DNS discovery, filtered
  by the liveness the peer health tracking already maintains.
- **Roles.** Group Ready peers by region; the gateway is the lowest node URL
  in each group. Roles are re-derived on every membership change.
- **Overlap over gaps.** A node that sees no Ready gateway for its own region
  takes the role until it sees one. Two gateways cost one duplicate
  cross-region fetch and self-correct; zero cuts the region off.

Everything below the role — the feed, the region-keyed watermark map carried
in the feed envelope, the pass-start buffer — is identical to the managed
path. What is missing is the authority: no primary designation, so "complement
of the primary" does not apply; no rollout orchestrator, so no suspension, no
caught-up gating on promotion, and no staleness re-designation. Role changes
are more frequent and less ordered, and the region watermark (§4.3) is what
keeps them cheap.

The degraded case is worth noting because it is graceful: a mesh in which
every node is a region of one derives a full gateway clique — exactly today's
all-to-all topology and cost, never a gap.

---

## 3. Replica sync (intra-region)

### 3.1 Pull with long-polling, over a trimmed arrival index

Both links pull, and both long-poll. Using one mechanism for both is worth more
than tuning each: one endpoint shape, one cursor discipline, one set of failure
modes, and no push path left to maintain.

The structure the sibling reads is a **bounded change feed**, not a live index:

- **Key** `sync/fwd/{seq:u64 BE}` under a new prefix in an existing column
  family. **Value**: the operation without its body — the same two shapes
  `ReplicationOperation` has today, `upsert_artifact` (producer, namespace,
  key, artifact id, `version_ms`, size, inline flag, branch and trunk) and
  `delete_namespace` (namespace, `version_ms`). One row per *change*, not per
  live artifact; namespace deletes are rows like any other, so the sibling
  link carries them losslessly.
- **`seq`** comes from a persisted per-node counter, monotonic across restarts
  and independent of any wall clock. The row is written in the same batch as
  the change it describes, so a crash cannot separate them.
- **Written for what the sibling does not have.** A client write and a
  region-sync apply each produce a row. A change pulled *from the sibling*
  never does — its only consumer already has it, and without this rule the two
  replicas would echo every record back and forth forever. Nor does an apply
  that changed nothing (last-writer-wins kept the local record).
- **Always maintained.** A region of one has no consumer and its feed simply
  churns at the cap. Switching the feed off without a sibling would save that
  churn but reopen a race the moment one appears — the sibling snapshots the
  head before the source starts writing rows — so it stays on.
- **Trimmed from below.** Every request carries the sibling's cursor, and the
  source deletes rows at or below it in a batched trim — with one consumer per
  direction, that position is a single number.
- **Capped from above, dropping oldest.** If the sibling is absent or slow the
  feed reaches its cap and the oldest rows go, exactly as the segment ring drops
  its oldest content. **Writes are never blocked** — which is the whole failure
  mode the outbox's depth cap produces today. The default cap is **1,000,000
  rows** (about 100 MB at the feed's ~98 B a row, ~80 MB on disk); the sizing
  rule is that it must hold the writes that land during the longest backward
  pass the sibling can need, which is what keeps the recovery below from
  looping.
- **Descriptors only.** A page carries rows, not bodies; the puller fetches
  bodies — inline or segment-backed — through the same pipelined fetch and
  apply stages the backward pass already uses against
  `/_internal/backfill/bodies` and `/_internal/backfill/artifacts/{id}`. So
  the forward read is only a different lister feeding an existing pipeline,
  a page stays small and bounded however large the entries behind it, and the
  receiver applies its own admission before bytes move. The extra round trip
  is sub-millisecond on loopback.

The endpoint is `GET /_internal/sync/forward?after={seq}&wait=30s`, and its
contract is three cases:

- **`after` at or above the floor** — returns `{entries, next, head}`,
  blocking up to `wait` when nothing is above the cursor, so a sibling
  converges in milliseconds without polling. `head` is the source's newest
  seq; `head - next` is the sibling's lag in rows.
- **`after` omitted** — returns `{head}` immediately, with no entries. This is
  the snapshot a bootstrapping sibling takes before its backward pass.
- **`after` below the floor** — `410 Gone` with `{floor, head}`. The rows
  between were dropped; the sibling has fallen off the feed.

A sibling with no cursor (cold, restarted without one) and a sibling that
receives `410` do the same thing: **snapshot `head`, run the horizon-bounded
sync backward pass, then read forward from the snapshot.** Everything committed
before the snapshot is in the index the pass lists; everything after it is in
the feed above the snapshot. That is the same recovery a cold node already
uses, so the cap introduces no new mechanism — only a new reason to enter one
that exists — and the pass is the full horizon-bounded one rather than a
narrower window, because the sibling that fell off may have missed old records
that region sync delivered late.

The trade is deliberate and worth stating plainly: **bounded storage and
never-blocked writes, in exchange for a recovery path when a sibling falls far
enough behind.** On loopback, falling that far behind means the sibling was down,
which is exactly when a backward pass is appropriate anyway.

### 3.2 One lane, in commit order

**Drop the metadata/bulk lane split.** Today lane `0` (inline artifacts, which
includes every action-cache entry) drains with strict priority over lane `1`
(segment-backed bodies), so an entry written *after* its blobs is delivered
*before* them. That inversion is why the strand cascade needs a grace window,
commented in the code as "a young stranded entry is kept — its blobs may still
be mid-replication".

The split exists to stop small entries queueing behind gigabytes, which is a WAN
argument. On loopback a large body transfers in seconds, so the head-of-line
cost it avoids is small while the inversion it imposes is permanent. One feed,
consumed in commit order, restores blobs-before-entry for free.

Measure afterwards: the delay a multi-GB body imposes on entries committed
behind it over loopback. If it turns out to matter, the fix is a deadline that
defers the body and advances — never a second lane, which would reintroduce the
inversion.

### 3.3 Serving is gated on the blobs, not on the ordering

Do not depend on replication delivering a blob before the `ActionResult` that
references it. That ordering is fragile — a lane split inverts it, a deferred
body skips past it — and when it breaks, the failure is a hit whose outputs
cannot be fetched.

Depend on a local check at serve time instead: **do not serve an action-cache
entry whose referenced blobs are absent.** `referenced_blob_keys` and the
reverse index already compute the dependency. Ordering then becomes an
optimisation that reduces how often the check bites, rather than the thing
correctness rests on.

### 3.4 Replicas are not identical, and that is fine

They cannot be. During the drain overlap both take writes, so neither is a
superset. Three things keep a primary flip from hurting, none of which need
identity:

- **Bidirectional loopback sync**, so write-divergence is transient and
  self-healing — milliseconds, not minutes.
- **The serve-side gate** above, so residual divergence is an honest miss.
- **Flip rarity**, which `choosePrimaryPod` already provides.

### 3.5 A departing node waits to be pulled

Push let a departing node ship its tail on the way out. Pull cannot — the tail
is whatever the sibling has not asked for yet — and the tail is exactly the
recent writes the requirements single out. So the shutdown sequence gains one
step. On termination the node enters draining as it does today (public
requests rejected, `/_internal/*` still served), and then **waits until the
sibling's cursor reaches its head, or until the termination grace period less
a margin runs out**, before it exits. With the sibling long-polling
continuously, the wait is normally nothing: the cursor is already at head.

An expiry is a counted event, not a loss: the feed is on the persistent
volume, so the recreated pod serves the tail when it comes back and the
sibling merely lags for the restart. The one genuine loss is a node move on
local-path storage, where the volume itself is gone — which is the pre-existing
loss of that storage class, not something this design introduces.

### 3.6 Readiness follows the sibling, never the region

`/ready` latches when the replica bootstrap settles: the backward pass against
the sibling completed and the forward cursor is within one page of the
sibling's head. Without a sibling it settles immediately, and the existing
ring-fullness latch is kept as the cold-but-useful escape it is today.

Region sync never gates readiness, and neither does the gateway role. Both are
best-effort by requirement, a region of one has nothing to wait for, and a
replica that has never been gateway is no less able to serve. Readiness means
one thing: serving from this node will not cost hits its sibling would have
served.

---

## 4. Region sync (inter-region)

### 4.1 Two directions over the `version_ms` index

Both directions read the index `src/backfill/` already maintains — keyed by
inverted `version_ms`, one row per live artifact. No new structure.

- **Sync backward** walks newest → oldest, bounded by
  `max(horizon, watermark - buffer)`, and runs when a gateway enters or leaves
  the mesh, on restart, and on promotion. Newest-first is what a
  capacity-bounded ring wants when it has to choose.
- **Sync forward** reads ascending from the region watermark toward newest, and
  runs continuously. Ascending matters: the range is consumed contiguously, so
  the watermark can advance as the node goes rather than only on completion.

Long-polling applies here too — the forward read blocks until the peer has rows
above the watermark — so cross-region convergence is bounded by transfer time
rather than by a poll interval. The maximum blocking window is the same 30
seconds as the replica link; a failed read retries on the backoff the backfill
already uses (250 ms doubling to 5 s).

**The page cursor is the full index key, the watermark is only its
`version_ms`.** `version_ms` has millisecond granularity and a busy region
writes many records in a millisecond, so a cursor that were the bare watermark
would either skip the rest of a tie or re-list a tie larger than a page
forever. `/_internal/backfill/entries` already pages by the full key as an
opaque `after`; the ascending read does the same. Within a connection the
cursor is that key; what is persisted and shared (§4.3) is the `version_ms` of
the last consumed entry, and a resume from a watermark alone starts at
`(watermark, "")` inclusive — re-listing at most one millisecond's worth of
entries, which are skipped as already present.

### 4.2 The watermark is `version_ms`, anchored to observed data

- **Not wallclock.** Anchoring to the local clock assumes the gap between "now"
  and "the newest record I have actually received from this peer" is zero. That
  gap *is* the propagation delay — writer to replica to gateway to remote
  gateway — and a wallclock watermark advances straight past it, whether or not
  anything was consumed, and even when a pass fails.
- **Max `version_ms` observed in the listing**, not max applied. Precisely: *the
  highest `version_ms` among the entries the peer returned*, regardless of what
  this node then did with each one. An entry skipped because the record is
  already present locally counts. So does one the capacity rule declined, and
  one that resolved `Absent` when fetched. What matters is that the peer showed
  it, not that it was needed.

  Max-*applied* would stop advancing the moment you are converged — nothing to
  apply, so nothing learned — and you would re-list the same range forever.
- **One per remote region, keyed by region rather than by the node currently
  holding its gateway.** A single global watermark would skip records: if you
  pulled everything at or above T from one region and advanced past T, records
  at or above T that only another region holds are never requested. Keying by
  region rather than node matters because the remote role moves on every one
  of its deploys: a node-keyed watermark would start from nothing each time
  and cost a full horizon-bounded pass, in every region, per remote deploy. A
  region-keyed one is sound for the same reason §4.3 gives — the remote
  replicas are lossless siblings, so what the old gateway had shown, the new
  one holds — and a remote re-designation is just "a gateway entering", which
  runs the buffered backward pass of §4.4 against the new node.
- **Advance contiguously.** Because the forward read is ascending, the watermark
  moves to the last entry consumed without a gap behind it. A read that fails
  part-way keeps whatever contiguous prefix it consumed and resumes there. The
  backward pass keeps the stricter rule — it lists descending, so it advances
  its watermark only on completing the pass.

### 4.3 The watermark is region state, replicated between replicas

Carry the `{remote_region -> version_ms}` map in the replica-sync page envelope
— a few dozen bytes — and **merge by max**. Both replicas then hold the region's
current position, so a promoted gateway starts from where the region actually
is, and a demoted one does not sit on a stale value.

This is sound *because replica sync is lossless*. Adopting the sibling's
watermark asserts something about your own coverage, which is the objection that
sank earlier cursor-inheritance schemes — but here anything the gateway acquired
below the watermark reaches its sibling over the sibling link regardless. That
link is the delivery path; the cross-region one is not. The strict intra-region
guarantee is exactly what licenses the loose inter-region sharing.

Max is the right merge because a watermark is a monotone claim about the
*region's* coverage, and the replicas converge, so a claim by either is a claim
for both — including when one holds a higher value from an earlier stint as
gateway.

**And this is why the gateway flipping every deploy is harmless.** In a
`version_ms` model a missing watermark has a natural default: `compute_window`
returns `horizon.max(None)` = the horizon, so a promoted gateway with no
watermark does one horizon-bounded pass. With the map replicated it does not even
need that. A sequence cursor has no meaningful default, which is why every
earlier draft needed inheritance machinery to survive a flip.

### 4.4 Buffer at pass start only

Continuous forward reads use the watermark directly. Records arrive at a gateway
in near-`version_ms` order, and the gateway clique gives multi-source
redundancy: a late arrival is missed only if *every* gateway acquired it late
relative to your watermark on that gateway. If one gateway is partitioned for an
hour and heals with a batch of hour-old records, you were pulling the same
records from the others throughout.

A backward pass that *starts* — discovery, restart, promotion — widens its bound
instead:

```rust
min_version_ms: horizon.max(peer_watermark_ms - buffer)
```

The horizon **floors** it, so the buffer can never push the pass below the
horizon however large it is set. It is self-limiting, which makes choosing the
value low-stakes: pick generously and the horizon caps the work. This is a
one-line change to `compute_window`, not a new pass type.

The buffer has to cover what was in flight when the watermark last advanced —
writer to replica to gateway to remote gateway — and the long tail of that is a
multi-GB body mid-transfer, not clock drift. The default is therefore **10
minutes**, replacing the 60-second skew allowance the walker carries today for
the same slot. The cost of a generous value is listing, not fetching: ten
minutes of a busy region's writes is a few thousand ~100-byte rows, presence-
checked and skipped.

### 4.5 Store-and-forward is accepted for now

A non-gateway can only fetch an object once its gateway has materialised it, so
intra-region propagation of a large body starts only after the cross-region
transfer completes. The fix is cut-through — the gateway advertising chunks as
they land — but it is an optimisation to schedule after the topology works. The
cost of deferring is bounded and known: intra-region convergence of a large body
lags by roughly the transfer's own duration, which matters for the multi-GB tail
and not at all for the small objects that dominate by count.

### 4.6 Clocks

`version_ms` is stamped by the original writer's clock, and region sync orders
by it. Keying the watermark by region confines each region's own writes to its
own clock domain, but store-and-forward mixes domains: a gateway lists records
it holds from a third region under that region's stamps, and the watermark
takes the max. A region whose clock runs `d` behind the fastest one it shares
a listing with therefore has its own writes sort below the puller's watermark
for `d` after any faster-stamped record is observed, and the ascending read
does not look there.

The consequence is bounded by the buffer. Skew below it costs nothing that
lasts: the next backward pass — every deploy runs one — lists from
`watermark - buffer` and recovers the skipped range. Skew above it is a
standing inter-region miss for the slow region's writes until the clock is
fixed, which is the accepted-miss class of §7 with a cause that can be named.
So the requirement is stated rather than hidden: **clocks within the buffer of
each other**, trivially true for NTP-disciplined managed nodes and a
self-hosted operator's responsibility otherwise. Every listing response
carries the peer's `now`; the puller exports the difference as
`kura_peer_clock_skew_seconds{peer}` and alerts above the buffer, so a
violation shows up as a named cause rather than as an unexplained miss rate.
The intra-region link is unaffected — the feed is arrival-ordered and never
consults a clock.

### 4.7 Namespace deletes

`DeleteNamespace` is the only removal that replicates, and it is a row in the
`version_ms` index (`NamespaceTombstone` kind) exactly as it is today, so both
region-sync directions list it and apply it through `apply_tombstone`. The
anti-resurrection guard stays where it is: the tombstone row in
`ROCKSDB_CF_NAMESPACE_TOMBSTONES` gates every persist path locally, so an
upsert older than a tombstone loses whichever order the two arrive in.

The residual `window.rs` already reasons about carries over unchanged. The
backward bound `max(horizon, watermark - buffer)` applies to tombstones as to
everything else — a kind-specific exemption would mean walking past the bound
to the peer's oldest entry on every pass. A tombstone newer than the last
completed pass is always listed; only the horizon term can raise the bound
above it, and it does so only when this node's ring turned over while it was
away, by which point the artifacts that tombstone would have removed are older
than the horizon and heading for eviction. Inside a region the question does
not arise: tombstones are feed rows, and the feed is lossless.

### 4.8 The bandwidth limiter stops at the region boundary

The adaptive limiter is shared across replication uploads, ingests and backfill
fetches and paces itself against public load — a WAN-oriented ceiling. It
applies to cross-region transfers only. **Same-region peers, as the peer list
defines them, bypass it**: the traffic is loopback, the link is the one the
lossless requirement rides on, and throttling it to protect a WAN it never
touches would slow a rollout's convergence for nothing. The memory-pressure
admission is unchanged and still bounds what a fast sibling can push into a
node's RAM.

---

## 5. Migration

Mixed-version nodes run side by side, and in two of the three deployment models
some of them are not ours to upgrade. Every phase below therefore has to leave a
mixed mesh converging — worst case with duplicate deliveries, which
last-writer-wins absorbs.

### 5.1 The three models

| Model | Authority | Version control | Consequence |
| --- | --- | --- | --- |
| Managed regions + co-located instance | controller → server | ours, staged | Full sequencing available; the co-located instance is a region of one (§2.3) |
| Managed regions + self-hosted peers | server | ours *and theirs* | Self-hosted peers may lag arbitrarily; per-pair negotiation is mandatory |
| Fully self-hosted | none — local derivation (§2.4) | theirs | Capability negotiation still works peer to peer; roles derive locally |

### 5.2 Phases

- **Phase 0 — additive, nothing changes behaviourally.** Add the arrival index
  (a new key prefix in an existing column family, never a new CF: the store
  opens with an explicit descriptor list, so a rollback to a binary that does
  not know the CF fails to open the database). Add
  `GET /_internal/sync/forward`, add the ascending read to the existing backfill
  listing, and advertise both in `/_internal/status`. The server starts
  publishing `{region, gateway}` in the peer list; older nodes ignore fields
  they do not know. Push still does all the work.
- **Phase 1 — negotiate per pair.** A node that sees a peer advertising the pull
  capability stops pushing to that peer and lets it pull instead. Each direction
  of each link negotiates independently, so new↔new pairs use pull while any
  pair touching an old node stays on push. Which pull a pair uses follows the
  `region` field Phase 0 published: same-region pairs use the feed, every other
  pair uses the `version_ms` reads with a region-keyed watermark — pulling from
  both of a remote region's replicas advances the same watermark, which is
  sound because they are lossless siblings. A mixed mesh is correct throughout,
  merely redundant.
- **Phase 2 — narrow the topology.** Once every peer in a mesh advertises the
  capability *and* the server is publishing roles, a node stops exchanging with
  peers its role says it should not talk to. Before that, keep the all-to-all
  exchange: it is correct, just wasteful.
- **Phase 3 — remove the outbox.** Only when no supported peer still needs it.

Each phase is a config flag, and reverting the flag restores the previous
behaviour, because push and pull can coexist on the same link.

### 5.3 The constraint that decides the timeline

**Phase 3 is gated by the oldest self-hosted version still in the field, not by
our own rollout.** A self-hosted peer that never upgrades keeps every link
touching it on push, so the outbox has to stay compiled in — and its depth cap
keeps applying to those links — until the supported-version floor moves past
Phase 1. Plan for the outbox living alongside the new path for at least one
support window, and make sure the metrics distinguish the two so the remaining
push traffic is visible rather than assumed gone.

Phase 2 has the same shape in the mixed model: "every peer advertises" cannot be
evaluated globally when some peers are customers'. Evaluate it per mesh, and
degrade to all-to-all for meshes that contain an old node.

---

## 6. Observability

Per `kura/AGENTS.md`, every metric added or changed here needs a matching panel
in `infra/grafana-dashboards/tuist-kura-details.json`, with the operational
interpretation in the panel description rather than the Prometheus HELP text.
Counters scrape with a doubled suffix (`foo_total` is served as
`foo_total_total`), so panels must query the scraped name.

### 6.1 Retained, retired, reframed

| Metric | Fate |
| --- | --- |
| `kura_outbox_messages`, `kura_outbox_lane_messages` | Keep through Phase 2 — they measure the remaining push traffic, which is exactly what tells you whether Phase 3 is reachable. Retire with the outbox. |
| `kura_replication_*` (apply outcomes, latency, by target) | Reframe: `target` becomes the peer being pulled *from* rather than pushed *to*. Same families, inverted meaning — rename rather than silently repurpose. |
| `kura_backfill_*` | Retained. Backward sync is unchanged apart from the pass-start buffer. |
| `kura_capacity_shed_*` for outbox exhaustion | Should trend to zero as links move to pull, and its remaining non-zero share names the links still on push. |

### 6.2 Added

**Replica sync**

- `kura_sync_forward_cursor_lag_entries{peer}` and `_seconds{peer}` — how far
  the sibling is behind. On loopback this should sit near zero; sustained lag is
  the early warning for a flip landing on a cold replica.
- `kura_sync_forward_index_entries` — arrival-feed depth, bounded by the cap.
- `kura_sync_forward_index_dropped_total` — **drop-oldest events.** Non-zero
  means a sibling fell off the retained range and will need a backward pass. On
  loopback this should be approximately never, so it is an alert, not a gauge to
  watch.

- `kura_sync_forward_fell_behind_total` — the puller's side of the same event:
  a `410` received. One per drop event is expected; a climb during recovery
  means the cap is smaller than the sizing rule requires.
- `kura_sync_forward_drain_timeout_total` — a departing node exited before the
  sibling reached its head (§3.5). Recent writes lagged for the restart.

**Region sync**

- `kura_region_sync_last_success_age_seconds{region}` — time since the last
  successful forward read from that region, empty reads included. The primary
  inter-region health signal and the input to re-designation (§2.2).
- `kura_region_watermark_age_seconds{region}` — lag, meaningful while the
  remote region is writing; not a health signal on its own.
- `kura_region_sync_cycle_duration_seconds`, `_entries_listed`,
  `_bytes_fetched{region}` — cost and progress per cycle.
- `kura_peer_clock_skew_seconds{peer}` — peer `now` minus local `now` from
  each listing response (§4.6).

**Topology**

- `kura_gateway_role{state="gateway|standby|suspended"}` — one series per node,
  so a region with zero or two gateways is visible directly.
- `kura_gateway_role_changes_total` — churn; a step change after a deploy is
  expected, a continuous climb is not.
- `kura_gateway_suspension_expired_total` — the timeout in §2.1.1 firing.

### 6.3 Alerts

| Alert | Condition | Why it matters |
| --- | --- | --- |
| Gateway cut off | `kura_region_sync_last_success_age_seconds` above 5 min for every remote region | The node's cross-region path is broken; also the re-designation trigger |
| Region pair stalled | the same, for one remote region only | The path between two regions is stuck; a role move cannot fix it, so it is a page rather than an action |
| Gateway suspension expired | `kura_gateway_suspension_expired_total` increases | A rollout wedged; replication was restored by timeout rather than by completion |
| Region without a gateway | no series with `state="gateway"` for a region beyond the transient window | INV-3 violated |
| Sibling fell off the feed | `kura_sync_forward_index_dropped_total` increases | Loopback should never be slow enough for this |
| Drain gate expired | `kura_sync_forward_drain_timeout_total` increases | Recent writes lagged for a restart; the sibling was down or the grace period is too short |
| Clock skew above the buffer | `kura_peer_clock_skew_seconds` beyond 10 min | The slow region's writes are a standing inter-region miss until fixed (§4.6) |
| Push traffic not declining | `kura_outbox_messages` non-zero on links expected to have migrated | Phase progress is not what was assumed |

---

## 7. Invariants

Rules an implementation may not break. Each fails *silently* when violated.

**INV-1 — the region-sync watermark is anchored to observed `version_ms`, never
to a local clock.** A wallclock watermark advances past records still in flight.

**INV-2 — never advance a watermark past a range you have not consumed.** The
value is the highest `version_ms` the peer returned, counting entries skipped as
already-present, declined by capacity, or found `Absent` — never max applied,
never the pass start time. A forward read advances to the last contiguously
consumed entry; a backward pass advances only on completion, because it lists
descending and being *shown* the newest entry is not the same as having consumed
the range.

**INV-3 — never publish zero gateways for a region with a Ready node**, other
than transiently while the holder restarts or while a rollout suspension is in
force. Two gateways during a transition cost one duplicate transfer and
self-correct; zero cuts the region off.

**INV-4 — a node talks only to the peers its role names.** Non-gateways never
open a cross-region link. A stuck cross-region path is fixed by re-designation
(§2.2), not by routing around it — the exception being the serverless
self-hosted mode, where the node derives its own role because there is no
authority.

**INV-5 — never designate a gateway that is about to be drained.** The role
would evaporate seconds later; and a bare "complement of the primary" rule hands
it to exactly that pod when serving flips (§2.1).

**INV-6 — a suspended gateway role must expire.** Suspending it for a rollout
stops the region's cross-region sync entirely. A wedged rollout would otherwise
stop it indefinitely and silently.

**INV-7 — do not serve an action-cache entry whose referenced blobs are
absent.** This, not delivery ordering, is what makes divergence produce a miss
rather than a broken build.

**INV-8 — the arrival feed is trimmed and capped, never allowed to block a
write.** Dropping the oldest rows is correct; refusing a write because the feed
is full is the failure this design exists to remove.

**INV-9 — `delete_everything` (`version_ms == 0`) stays node-local.** It writes
no tombstone and enqueues nothing today, and must not acquire replication state
either.

**INV-10 — eviction never propagates.** Every node evicts under its own
capacity; propagating would couple decisions that are deliberately independent.
The cost of silence is a stale who-has-what hint, which resolves as `Absent` on
fetch.

Accepted, not invariant — the two misses the requirements permit:

- **Inter-region: a record reaching a source with a `version_ms` older than
  `watermark - buffer` is never requested**, because the listing is ordered by
  `version_ms` and it sorts below where you look. No buffer size eliminates
  that — only arrival-ordered listing would. Clock skew above the buffer (§4.6)
  is this miss with a nameable cause.
- **Intra-region: a feed row dropped at the cap for a record whose
  `version_ms` is below the horizon** — an old record that region sync
  delivered late — is not recovered by the backward pass, which is
  horizon-bounded. It needs a sibling down long enough to fall off the feed
  *and* a stale arrival in that window, and the record was heading for
  eviction anyway.

---

## 8. Cost, measured

Measured on one node: a real `bazel build //:kura` against a local instance
(4,458 objects, 560 MB) plus a synthetic 2 KiB fill (92,993 objects), with the
index read back through `ldb`.

| Column family | rows | logical bytes | B/row |
| --- | --- | --- | --- |
| `manifests` | 97,451 | 19,206,357 | 197 |
| `key_value`, of which `backfill/idx/` | 99,365 (97,451) | 9,773,266 (**9,160,394**) | **94.00** |
| `segment_artifacts` | 96,722 | 9,768,922 | 101 |
| `action_cache_index` | 729 | 104,247 | 143 |
| **total** | | **38,853,027** | **399 per artifact** |

The `version_ms` index costs **exactly 94.00 B/row**, one row per live artifact.
After a clean-shutdown flush the store's SSTs came to 33.4 MB against 38.9 MB
logical — compression around 0.85, so ~80 B/row on disk. **Region sync adds
nothing to this**: both its directions read the index that already exists.

**The arrival feed is bounded by its cap, not by the dataset.** This is the
significant change from earlier drafts, which proposed a live index with one row
per artifact and therefore a ~25% increase in the metadata store. A trimmed feed
holds one row per *unconsumed change*: at ~98 B a row, the default cap of one
million rows is about 100 MB logical, ~80 MB on disk, independent of how many
artifacts the node holds. With a sibling pulling over loopback the steady-state
depth is near zero; a region of one sits at the cap, which is the bounded price
of keeping the feed always on (§3.1).

Memory follows from that. The feed's index blocks are proportional to its
retained size, not to the artifact count, so they are a fraction of a MB at any
sensible cap. Two things still matter:

- **Issue sync reads with `fill_cache = false`.** Every iterator is built with
  default `ReadOptions` today, so `fill_cache = true`; a cursor scan reads each
  block once, and caching those blocks is pure eviction pressure on the manifest
  blocks the read hot path needs. This also fixes the same pollution in the
  existing backfill listing.
- **The write path gets cheaper.** One feed row per commit replaces `N-1` outbox
  rows in the synchronous batch, plus their later deletes — and the feed's own
  deletes are batched trims rather than one per delivery.

---

## 9. Rejected alternatives

Each looks obviously better until worked through. Recorded so they are not
re-proposed.

**Two lanes intra-region (metadata priority over bulk).** Discards the write
order, which is load-bearing: an `ActionResult` commonly references a blob
written milliseconds earlier. It is what today's split already does, and the
strand grace window exists to absorb it. §3.2.

**Origin-keyed indexing — key rows by `(origin_node, origin_seq)` so cursors
become portable.** Eviction kills it. A node's holdings of any origin are sparse,
and sparse *differently* from its peers: if a peer holds B:1–1000 and
B:5001–6000, a puller that takes 6000 as its position has silently skipped
1001–5000 and will never ask anyone for them again. Dynamo-lineage systems handle
this with dots-and-gaps, but there the gap set *collapses* because every dot
eventually arrives; in an evicting cache the gaps are permanent, so the structure
grows and never compacts.

**Pruning a *live* index below the slowest peer's cursor.** Distinct from the
arrival feed's trimming, which is correct: a feed row is a change, and a consumed
change is genuinely spent. A *live* index holds one row per artifact, so nothing
accumulates and pruning would delete rows for artifacts still being served —
destroying the presence answer and reintroducing a falloff cliff for a saving
that does not exist.

**A WebSocket instead of long-polled HTTP.** Its central advantage is
server-initiated push, which is what this design removes — the receiver sets the
pace. The efficiency argument does not apply either: few, large,
request-response-shaped exchanges, so framing savings are under 0.1%. It would
cost the HTTP status codes the migration depends on, the request-scoped
middleware, and clean handling of the 300s connection recycling. If a persistent
stream is ever wanted, gRPC server-streaming on the existing h2c listener beats
it.

**Cursor-inheritance machinery** — published cursor maps, snapshot pairing,
catch-up gates, continuous shadowing by siblings, readiness-to-inherit signals,
drain-window handshakes. All of it existed to survive a gateway flip under
sequence cursors. A `version_ms` watermark has a natural default and is
region-replicated, so the flip is free. §4.3.

**Every node tailing every remote gateway** to keep all cursors warm. Buys a
rare event with roughly `N(R-1)` permanent extra streams — most of the
connection saving the gateway topology exists to produce.

**Coupling sibling eviction** so replicas stay content-identical. Cannot deliver
identity anyway, since both take writes during the drain overlap, so it buys a
smaller miss burst at the cost of coupling two nodes' capacity decisions. §3.4.

**A node-side bypass of a lagging gateway.** The failure it addresses —
unreachable gateway — is already handled by re-designation, and the one case
re-designation misses (Ready and heartbeating, WAN broken) is better fixed by
reporting read staleness so the authority can move the role. A bypass would
put topology decisions in two places at once. §2.2.

---

## 10. Parameters

Every value the design depends on, with its default and the rule that chose
it. They are configuration with defaults, not open questions; the rule is what
to re-check when a measurement disagrees.

| Parameter | Default | Rule |
| --- | --- | --- |
| Pass-start buffer (§4.4) | 10 min | Covers the in-flight propagation when the watermark last advanced; the tail is a multi-GB body mid-transfer. Cost is listing only, horizon-floored. Re-check against the observed distribution of (arrival at a gateway − `version_ms`). |
| Feed cap (§3.1) | 1,000,000 rows (~100 MB) | Must hold the writes that land during the longest backward pass a sibling can need, or recovery loops. Re-check against peak write rate × cold-pass duration. |
| Long-poll wait (§3.1, §4.1) | 30 s | Well inside the 300 s connection recycling; bounds how long a cleanly idle link goes without a proof of life. |
| Retry backoff after a failed read (§4.1) | 250 ms → 5 s | The backfill's existing constants. |
| Cut-off threshold (§2.2) | 5 min, every remote region | Ten consecutive failed long-polls; short enough to matter, long enough that a slow transfer is not a failure. |
| Re-designation cooldown (§2.2) | 15 min | Long enough that a failure the new gateway shares with the old cannot flap the role faster than someone can look. |
| Suspension expiry (§2.1.1) | 30 min | A rollout longer than this is already abnormal; restoring early is safe because the designation rules still apply. |
| Concurrent suspensions (§2.1.1) | 1 per mesh | Guarantees cross-region sync never pauses mesh-wide; a second rolling region absorbs the churn instead. |
| Readiness lag (§3.6) | one page of the sibling's head | Caught up for every purpose that costs a hit. |
| Drain wait (§3.5) | termination grace period − margin | The wait is normally zero; the bound is the pod's, not a new one. |
| Clock skew alert (§4.6) | above the buffer | Below it the next backward pass recovers the skipped range; above it the miss stands. |
