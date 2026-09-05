# Kura Replication Design

Status: proposed. Not implemented, not scheduled.

This document is the design only. The analysis behind it — why the current
mechanism does not scale, what else was considered, the options deliberately
left out — lives in [`replication-scaling.md`](replication-scaling.md).

Two orthogonal axes run through everything below. **Which link** — the
intra-region *replica* link or the inter-region *region* link — decides the
guarantee and the cost. **Which phase** — *sync backward* to catch up on
history, *sync forward* to stay current — decides the structure each link uses:

| | **replica** (intra-region) | **region** (inter-region) |
| --- | --- | --- |
| **sync backward** — catch up | `version_ms` index, horizon-bounded; on cold start or restart | `version_ms` index, horizon-bounded; on a gateway entering or leaving the mesh |
| **sync forward** — stay current | arrival index or outbox, commit-ordered | `version_ms` index + region-gateway watermark, continuous |

---

## 1. Requirements

The two links have different jobs, and conflating them is what made earlier
drafts complicated. Stated separately:

| | **replica sync** (intra-region) | **region sync** (inter-region) |
| --- | --- | --- |
| Latency | fast — a rollout must not cost cache hits | slower is fine |
| Completeness | **no records lost**, especially recently written ones | best effort; missing records in edge cases is acceptable |
| Cost | loopback, effectively free | metered WAN |
| Peers | one sibling (or a few) | one gateway per remote region |

Everything below follows from that split. The strict guarantee is bought where
it is cheap; the loose one is accepted where it is expensive.

---

## 2. Topology: one gateway per region

> Each region designates a gateway. Gateways exchange entries with each other.
> A gateway exchanges entries with the non-gateways of its own region. A region
> has at least one gateway, normally exactly one. "Exchange" means both sides
> pull.

WAN cost becomes `(R-1) x S` by construction rather than `(N-1) x S`: bytes
cross a region boundary once and spread over loopback inside it. Roles also
make egress shaping attributable, which matters because per-tenant shaping is
per-pod and a gateway's ceiling has to cover its whole region's cross-region
traffic.

**Bidirectionality inside the region is load-bearing**, not symmetry for its own
sake: the gateway pulling *from* its non-gateways is the only way data written
on a non-gateway leaves the region. During a rollout both replicas take writes
for the drain overlap, so neither is a superset of the other and the link has to
work both ways.

### 2.1 The gateway is the complement of the primary

Do not create a second designation. The gateway is derived from the one that
already exists:

- **Two or more replicas** — the gateway is a Ready, non-draining replica that
  is *not* the primary. Cross-region work then lands off the node serving
  clients, which is the point of having a standby at all.
- **One replica** — that instance is both primary and gateway.
- **No eligible non-serving replica** — the primary takes the role rather than
  the region losing it.

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

Better than absorbing that churn is not to have it. The controller owns both the
rollout and the designation, so it can **suspend the gateway role for the
duration of a region's rollout and designate once when the rollout reaches a
terminal state**.

"Terminal" must include **failed**. A rollout that errors out must still get a
gateway assigned, or the region is left indefinitely out of sync — the failure
mode that matters most, because a failed rollout is precisely when nobody is
watching the replication topology.

While suspended the region does no cross-region sync at all. That is acceptable:
inter-region convergence is explicitly allowed to lag, and a deploy is minutes.
In exchange, no role moves mid-rollout, no pod is designated while draining, and
the first pass after re-enabling covers the whole suspension window through the
pass-start buffer (§4.4).

**The suspension must expire.** A rollout that wedges — and they do — would
otherwise stop cross-region replication for that region indefinitely and
silently. Bound it with a timeout that restores the role regardless of rollout
state, and alert on the timeout firing rather than on the suspension itself.

Worth watching if several regions deploy at once: independently suspending every
region pauses cross-region sync mesh-wide. Staged rollouts avoid it; simultaneous
ones should be capped so that at least one region stays live.

### 2.2 What the server publishes

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

And the rule nodes hold to: a stale view keeps working — do not fail closed —
and a node may **bypass** a gateway that is unreachable or lagging past a
threshold. It may never **promote** itself. Self-promotion is fighting the
authority, and the only deployment where a node decides its own role is the
serverless self-hosted mode (§2.3), where there is no authority to fight.

### 2.3 Self-hosted deployments

Two shapes, and they degrade differently.

**Enrolled self-hosted nodes** — those that talk to the server — need no special
handling. They fetch the same peer list over the mesh heartbeat and read their
role from it exactly as a managed pod does. The controller is absent, so the
server resolves roles from what it can see (registered endpoints, their reported
`traffic_state`, their liveness) rather than from a `KuraInstance` status.

**Fully self-hosted meshes with no server** have no authority at all, so each
instance has to act as its own. Every node already sees the same membership —
static `KURA_PEERS` plus DNS discovery — so the roles can be derived from a
deterministic rule over that shared view: group peers by region, and the gateway
is the lowest node URL among the Ready members of each region.

That is a genuinely weaker mode and the design should say so rather than pretend
otherwise:

- Views can diverge transiently, so bias toward overlap — a node that sees no
  gateway for its own region takes the role. Two gateways cost one duplicate
  cross-region fetch and self-correct; zero cuts the region off.
- There is no primary designation without the controller, so "complement of the
  primary" does not apply. The deterministic rule stands on its own.
- There is no rollout orchestrator, so no suspension (§2.1.1) and no
  caught-up gating on promotion. Role changes are more frequent and less
  ordered; the region watermark (§4.3) is what keeps them cheap.

This mode is worth specifying properly before it ships, not inferring from the
managed path. It is out of scope for this document beyond the sketch above.

---

## 3. Replica sync (intra-region)

### 3.1 One lane, in commit order

**Drop the metadata/bulk lane split.** Today lane `0` (inline artifacts, which
includes every action-cache entry) drains with strict priority over lane `1`
(segment-backed bodies), so an entry written *after* its blobs is delivered
*before* them. That inversion is why the strand cascade needs a grace window,
commented in the code as "a young stranded entry is kept — its blobs may still
be mid-replication".

The split exists to stop small entries queueing behind gigabytes, which is a WAN
argument. On loopback a large body transfers in seconds, so the head-of-line
cost it avoids is small while the inversion it imposes is permanent. One lane,
drained in commit order, restores blobs-before-entry for free.

Measure afterwards: the delay a multi-GB body imposes on entries committed
behind it over loopback. If it turns out to matter, the fix is a deadline that
defers the body and advances — never a second lane, which would reintroduce the
inversion.

### 3.2 Serving is gated on the blobs, not on the ordering

Do not depend on replication delivering a blob before the `ActionResult` that
references it. That ordering is fragile — a lane split inverts it, a deferred
body skips past it, a re-keyed row moves it — and when it breaks, the failure is
a hit whose outputs cannot be fetched.

Depend on a local check at serve time instead: **do not serve an action-cache
entry whose referenced blobs are absent.** `referenced_blob_keys` and the
reverse index already compute the dependency. Ordering then becomes an
optimisation that reduces how often the check bites, rather than the thing
correctness rests on.

With that gate, divergence between replicas produces an honest *miss* rather
than a hit whose outputs cannot be fetched — the difference between a slower
build and a broken one. It is what makes a primary flip safe despite the
replicas never being byte-identical.

### 3.3 Replicas are not identical, and that is fine

They cannot be. During the drain overlap both take writes, so neither is a
superset. Three things keep a primary flip from hurting, none of which need
identity:

- **Bidirectional loopback sync**, so write-divergence is transient and
  self-healing — milliseconds, not minutes.
- **The serve-side gate** above, so residual divergence is a miss.
- **Flip rarity**, which `choosePrimaryPod` already provides.

Coupling the siblings' eviction decisions was considered and rejected (§7): it
cannot deliver identity anyway, so it buys a smaller miss burst at the cost of
coupling two nodes' capacity decisions.

### 3.4 Mechanism: keep the push, or add a forward index

This is the one open decision (§8).

With a **single target**, today's outbox loses most of what is wrong with it:
one extra put per write instead of `N-1`, one slot against the depth cap instead
of `N-1`, no fan-out. A restarting sibling stays in the discovered-only history
so its queued messages are not pruned. Push to a sibling is already fast and
effectively lossless.

A **forward index** — a live index keyed by arrival sequence that the sibling
scans with a durable cursor — would additionally remove the depth cap from the
write path entirely, remove the outbox row from the synchronous commit batch,
and let the receiver apply its own admission rule before bytes move. Its
measured cost is in §6.

The recommendation is to ship the topology and region-sync changes first with
the existing push retained, and treat the forward index as a follow-up justified
by measurement — specifically, by how often outbox depth actually reaches the
client.

---

## 4. Region sync (inter-region)

### 4.1 It is the existing walker, run continuously

`src/backfill/` already lists a peer's `version_ms`-ordered index newest-first,
bounded by `max(ring horizon, per-peer watermark)`, fetches what it lacks in
batches, and advances a durable watermark. The change is that it runs
**continuously with an advancing watermark** instead of edge-triggered on
membership.

No new index, no cursors, no per-source position — the inter-region link reads
the index that already exists.

### 4.2 The watermark is `version_ms`, anchored to observed data

- **Not wallclock.** Anchoring to the local clock assumes the gap between "now"
  and "the newest record I have actually received from this peer" is zero. That
  gap *is* the propagation delay — writer to replica to gateway to remote
  gateway — and a wallclock watermark advances straight past it, whether or not
  anything was consumed, and even when a pass fails.
- **Max `version_ms` observed in the listing**, not max applied. Precisely:
  *the highest `version_ms` among the entries the peer returned*, regardless of
  what this node then did with each one. An entry skipped because the record is
  already present locally counts. So does one the capacity rule declined, and
  one that resolved `Absent` when fetched. What matters is that the peer showed
  it, not that it was needed.

  Max-*applied* would stop advancing the moment you are converged — nothing to
  apply, so nothing learned — and you would re-list the same range forever.
- **One per remote gateway.** A single global watermark would skip records: if
  you pulled everything at or above T from one gateway and advanced past T,
  records at or above T that only another gateway holds are never requested.
- **Advance only on completing the requested range.** The listing is
  `version_ms`-descending, so the newest entry arrives first; taking the
  watermark from it before consuming the rest of the range would skip everything
  below. A pass or cycle that fails part-way leaves the watermark untouched and
  re-lists from where it was — which is what the existing walker already does by
  advancing only on pass completion.

### 4.3 The watermark is region state, replicated between replicas

Carry the `{remote_gateway -> version_ms}` map in the replica-sync exchange —
a few dozen bytes — and **merge by max**. Both replicas then hold the region's
current position, so a promoted gateway starts from where the region actually
is rather than from scratch, and a demoted one does not sit on a stale value.

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
watermark does one horizon-bounded pass. With the map replicated it does not
even need that. A sequence cursor has no meaningful default, which is why every
earlier draft needed inheritance machinery to survive a flip.

### 4.4 Buffer at pass start only

Continuous cycles use the watermark directly. Records arrive at a gateway in
near-`version_ms` order, and the gateway clique gives multi-source redundancy: a
late arrival is missed only if *every* gateway acquired it late relative to your
watermark on that gateway. If one gateway is partitioned for an hour and heals
with a batch of hour-old records, you were pulling the same records from the
others throughout.

A pass that *starts* — discovery, restart, promotion — widens its bound instead:

```rust
min_version_ms: horizon.max(peer_watermark_ms - buffer)
```

The horizon **floors** it, so the buffer can never push the pass below the
horizon however large it is set. It is self-limiting, which makes choosing the
value low-stakes: pick generously and the horizon caps the work. This is a
one-line change to `compute_window`, not a new pass type.

### 4.5 Store-and-forward is accepted for now

Under pull, a non-gateway can only fetch an object once its gateway has
materialised it, so intra-region propagation of a large body starts only after
the cross-region transfer completes. The fix is cut-through — the gateway
advertising chunks as they land — but it is an optimisation to schedule after
the topology works. The cost of deferring is bounded and known: intra-region
convergence of a large body lags by roughly the transfer's own duration, which
matters for the multi-GB tail and not at all for the small objects that dominate
by count.

---

## 5. Invariants

Rules an implementation may not break. Each fails *silently* when violated.

**INV-1 — the region-sync watermark is anchored to observed `version_ms`, never
to a local clock.** A wallclock watermark advances past records still in flight.

**INV-2 — never advance a watermark past a range you have not finished
consuming.** The value is the highest `version_ms` the peer returned, counting
entries skipped as already-present, declined by capacity, or found `Absent` —
never max applied, never the pass start time. And because the listing is
descending, being *shown* the newest entry is not enough: the range has to be
consumed before the watermark moves.

**INV-3 — never publish zero gateways for a region with a Ready node**, other
than transiently while the holder restarts. Two gateways during a transition
cost one duplicate transfer and self-correct; zero cuts the region off.

**INV-4 — a node may bypass a dead gateway; it must not appoint itself one.**
Self-promotion under a controller means fighting the controller.

**INV-5 — never designate a gateway that is about to be drained.** The role
would evaporate seconds later; and a bare "complement of the primary" rule hands
it to exactly that pod when serving flips (§2.1).

**INV-6 — a suspended gateway role must expire.** Suspending it for a rollout
(§2.1.1) stops the region's cross-region sync entirely. A wedged rollout would
otherwise stop it indefinitely and silently, so the suspension needs a timeout
that restores the role regardless of rollout state.

**INV-7 — do not serve an action-cache entry whose referenced blobs are
absent.** This, not delivery ordering, is what makes divergence produce a miss
rather than a broken build.

**INV-8 — `delete_everything` (`version_ms == 0`) stays node-local.** It writes
no tombstone and enqueues nothing today, and must not acquire replication state
either.

**INV-9 — eviction never propagates.** Every node evicts under its own capacity;
propagating would couple decisions that are deliberately independent. The cost
of silence is a stale who-has-what hint, which resolves as `Absent` on fetch.

Accepted, not invariant: **a record reaching a source with a `version_ms` older
than `watermark - buffer` is never requested**, because the listing is ordered
by `version_ms` and it sorts below where you look. No buffer size eliminates
that — only arrival-ordered listing would. It is the inter-region miss the
requirements permit.

---

## 6. Cost, measured

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

The existing `version_ms` index costs **exactly 94.00 B/row**, one row per live
artifact. After a clean-shutdown flush the store's SSTs came to 33.4 MB against
38.9 MB logical — compression around 0.85, so ~80 B/row on disk. **Region sync
adds nothing to this**: it reads the index that already exists.

The optional forward index (§3.4) would add ~98 B logical / ~83 B on disk per
row, taking the metadata store from 399 to ~497 B per artifact — about **+25%,
not a doubling**. Row count is set by mean object size: the Bazel build shows
mean 125,673 B but median 2,832 B, p90 143 KB, p99 2.67 MB — so ~398k rows in a
50 GB ring, ~37 MB of index.

### 6.1 Memory, if the forward index is built

Three components, only one additive:

1. **Memtable — not additive.** Bounded by the shared write-buffer manager,
   whose budget is fixed and already subtracted from the anon admission budget.
   More frequent flushes and compaction, not more memory.
2. **Block-cache data blocks — avoidable.** Every iterator is built with default
   `ReadOptions`, so `fill_cache = true`. A cursor scan reads each block once,
   so caching them is pure eviction pressure on the manifest blocks the read hot
   path needs. **Issue sync scans with `fill_cache = false`** — one option, and
   it also fixes the same pollution in today's backfill listing.
3. **Index blocks — the only additive cost**, and cheaper than the existing
   index because the key is 17 bytes against 86: **~0.2 MB at 398k rows**,
   ~0.5 MB at 1M, ~2.5 MB at 5M.

With `fill_cache = false` this design costs single-digit MB of resident memory
at any plausible scale. Without it, the scans evict manifest blocks and the cost
is a read-latency regression no table here would predict.

---

## 7. Rejected alternatives

Each of these looks obviously better until worked through. Recorded so they are
not re-proposed.

**Two lanes intra-region (metadata priority over bulk).** Discards the write
order, which is load-bearing: an `ActionResult` commonly references a blob
written milliseconds earlier. It is what today's split already does, and the
strand grace window exists to absorb it. §3.1.

**Origin-keyed indexing — key rows by `(origin_node, origin_seq)` so cursors
become portable.** Eviction kills it. A node's holdings of any origin are
sparse, and sparse *differently* from its peers: if a peer holds B:1–1000 and
B:5001–6000, a puller that takes 6000 as its position has silently skipped
1001–5000 and will never ask anyone for them again. Dynamo-lineage systems
handle this with dots-and-gaps, but there the gap set *collapses* because every
dot eventually arrives; in an evicting cache the gaps are permanent, so the
structure grows and never compacts.

**Pruning index rows below the slowest peer's cursor.** Right mechanism for a
log, wrong one here: the index holds one row per live artifact, so nothing
accumulates and pruning deletes rows for artifacts still being served. It
destroys the presence index, reintroduces a falloff cliff, pins forever on a
decommissioned peer while truncating silently if you forget stale ones, and
makes sender state stateful again.

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
smaller miss burst at the cost of coupling two nodes' capacity decisions. §3.3.

---

## 8. Open decisions

1. **Replica sync: keep the push, or build the forward index?** §3.4. Decide on
   measurement — how often outbox depth actually reaches the client, and the
   commit-path cost of the outbox row in the synchronous batch.
2. **The pass-start buffer's value.** Self-limiting, so low-stakes, but it wants
   a number grounded in observed propagation delay rather than the 60s skew
   allowance it inherits.
3. **Region-sync cycle period**, which sets inter-region convergence latency.
4. **Whether to rename to replica/region sync in code**, or keep the existing
   replication/backfill vocabulary and change only the triggering.
