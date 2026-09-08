# Kura Replication Design

Status: implemented on branch; see [`replication-implementation.md`](replication-implementation.md).

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

## 0. The problem this replaces

Replication today is **direct mail with per-target durable queues**. A write
enqueues one outbox row *per peer* inside the same synchronous RocksDB batch as
the manifest commit; a background worker drains those rows and pushes each to
its peer. Two lanes give inline artifacts strict priority over segment-backed
bodies; receivers apply and never forward; catch-up is a separate walker,
edge-triggered on membership changes and bounded by a recency horizon. The
full mechanism and the analysis are in
[`replication-scaling.md`](replication-scaling.md); the six limits it
identifies are what this design has to remove.

| | Limit | Why it is structural | Removed by |
| --- | --- | --- | --- |
| **L1** | **Fan-out lands on the hottest node.** Egress from the write-receiving node is `(N-1) x S`, and the cheap loopback copies share one pipeline with the expensive WAN ones. | The node under bursty client load is the node doing all the replication work. | Pull, so each receiver paces itself (§3, §4); the gateway topology, so bytes cross a region boundary once (§2). Not for a region of one — the co-located instance keeps `(R-1) x S` and now also serves the listings (§2.3). |
| **L2** | **Write availability is coupled to the slowest peer.** The outbox cap is now a per-peer share (#12826: 100k per target under a 1M ceiling), so a dead peer no longer sheds writes for the healthy ones — but a write is still refused with `429` the moment *any* of its targets is at its share, and the total grows with the mesh. | A queue bounded for safety cannot also be the convergence mechanism — Cassandra's hinted-handoff lesson. #12826 calls itself an interim measure for that reason. | A feed that drops oldest instead of blocking (§3.1, INV-7); no per-target queue at all. |
| **L3** | **Commit-path cost.** `N-1` extra puts in a synchronous batch per write, plus `N-1` later deletes, for data that is pure routing state. | It scales with mesh size on the critical path of every write. | One feed row per commit regardless of peer count, trimmed in batches (§3.1, §8). |
| **L4** | **Blind pushes.** The sender does not know what the receiver has or whether it will keep it; content addressing goes unexploited and bytes ship before the receiver's admission runs. | Push cannot ask; only a puller knows what it lacks. | Descriptor pages with receiver-side admission before bytes move (§3.1, §4.1). |
| **L5** | **No continuous anti-entropy.** Messages are dropped for targets that left the view, a rejoining peer re-walks only to the horizon, the walker is edge-triggered. | Convergence depends on a queue never losing anything and on membership events firing at the right times. | Continuous forward sync on both links (§3.1, §4.1), backward sync on every membership change (§4.1). |
| **L6** | **Priority is two-valued and global.** Two lanes, one inflight budget, one bandwidth limiter, no per-peer isolation. | A far peer's multi-gigabyte backlog occupies the slots the local sibling — whose convergence rollouts depend on — needs. | Two links with separate guarantees and separate mechanisms (§1); the limiter stops at the region boundary (§4.8). |

The design's own test is the table's last column: every limit maps to a
section, and a section that removed none of them would not be in the document.

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
cross a region boundary once and spread over loopback inside it. Because a
gateway lists only its own region's writes to the others (§4.1), its
cross-region egress is exactly `(R-1) x S_local` — deterministic, and the
gateway's — without the shaping needing to know about roles: per-tenant
shaping stays per-pod and role-agnostic, both replicas carry the class sized
for that share, and the non-gateway's unused headroom is borrowed under HTB.
The role can move without anything being re-rendered, so there is no
server-to-controller feedback path to build.

`R` is per account and small. A mesh is one account's instances, placed by
plan and traffic (#12901, #12956): a plan funds two, three or five regions,
and placement may *relocate* an account's instance or *expand* it into a
second region on the evidence of where its cache traffic comes from. Every
such move is a region entering or leaving the mesh — a backward pass, nothing
else — and the small `R` is what keeps the gateway clique, `R(R-1)` streams,
comfortably cheap.

**Bidirectionality inside the region is load-bearing**, not symmetry for its own
sake: the gateway pulling *from* its non-gateways is the only way data written
on a non-gateway leaves the region. During a rollout both replicas take writes
for the drain overlap, so neither is a superset of the other and the link has to
work both ways.

Non-gateways pull only from their own gateway; they never open a cross-region
link. A region's cross-region path is its gateway, and when that path is broken
the answer is an alert (§2.2), not letting other nodes route around it.

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
serves. If that ever changes, the tie-break is lowest ordinal among the
eligible, and the feed (§3.1) trims below the *lowest* consumer cursor rather
than the single one.

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

The instance's public peer Service is pinned to the gateway pod, the way the
client Services pin to the primary. It selected every pod, so a remote
gateway's listing pages could alternate between the two replicas; pinned, the
served listing is one node's, both directions of the region's WAN traffic stay
on the standby, and the selector doubles as the persisted designation the
controller reads back for stickiness — no new status field for that. The
headless Service keeps the broad selector (D-18).

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

### 2.2 What the server publishes, and what it does not decide

Publish roles as a **new field beside `peers`** in the existing mesh view —
`peer_roles: [{url, region, gateway}]` — and leave `peers` itself alone. It is
`Vec<String>` on every deployed node (`mesh_heartbeat.rs`, `enrollment.rs`);
retyping its elements would fail decode on an old node, which then keeps its
last-known view forever. A new field is ignored by old nodes and read by new
ones, which is the whole migration story for the topology.

Per-entry, not a bare boolean. A scalar tells a node its own role but not which
peer is its region's gateway or which remote peers are gateways, both of which
it needs in order to know who to pull from. One document then lets every node
derive the whole topology, which also makes it observable and testable. A
published role is used only while the node it names is present as a pulling
candidate; otherwise the local rule of §2.4 decides, which is what gives
overlap over a gap (D-7).

Rules the server holds to:

- Never publish zero gateways for a region that has a Ready node — except
  transiently while the holder restarts.
- Prefer overlap to a gap when moving it: two gateways for a transition window
  cost one duplicate fetch and self-correct; zero stalls the region. The window
  is **two heartbeat periods** — long enough for every node to have fetched the
  new list — and while it lasts, remote gateways pull from both of the region's
  published gateways and the pair inside the region both pull cross-region.
  The second listing shows records already present; bodies are fetched once.
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

**What the server does with that signal is alert, not re-designate.** The two
replicas of a region share a host, so they share its WAN path: a gateway whose
reads are stale against every remote region is almost always a region whose
path is broken, and moving the role to the sibling moves it onto the same
broken path. The one case a move would fix — a pod whose sync loop is wedged
while the pod stays Ready — is fixed by restarting that pod, after which the
ordinary rules place the role. So the server raises "gateway cut off" when a
gateway is stale against every remote region and "region pair stalled" when
it is stale against one, and leaves the topology alone in both. That keeps
every topology decision in one place, which is why nodes need no bypass rule
of their own: a node only ever talks to the peers its role says it talks to.

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
handling. They fetch the same peer list over the mesh heartbeat and read the
managed regions' roles from it exactly as a managed pod does. The controller
is absent and there is no primary designation to take the complement of, so
their own rule is the one the serverless mode uses — the gateway is the lowest
node URL among the region's Ready, non-draining members — and because every
node already applies that rule locally from the `traffic_state` and liveness
it probes, the server publishes nothing for them: `peer_roles` carries managed
regions only, where the server knows what the nodes cannot, the primary (D-7).

**Fully self-hosted meshes with no server** have no authority at all, so each
instance acts as its own, from the same inputs every node already has:

- **Region.** `KURA_REGION` is already required configuration. Each node
  reports it in `/_internal/status`, and the existing peer health probe reads
  it for every peer it already polls. A peer that reports no region — an older
  build — is treated as a region of one.
- **Membership and Ready.** Static `KURA_PEERS` plus DNS discovery, filtered
  by the liveness the peer health tracking already maintains.
- **Roles.** Group Ready peers by region; the gateway is the lowest node URL
  in each group. Roles are re-derived on every membership tick: the
  coordinator diffs the links the roles ask for (siblings; remote gateways
  while this node holds its region's gateway role) against the tasks running
  and opens or cancels the difference, so a role move costs one cancelled pass
  and one new bootstrap on the new holder — the brief pause §2.1 budgets for
  (D-15).
- **Overlap over gaps.** A node that sees no Ready gateway for its own region
  takes the role until it sees one. Two gateways cost one duplicate
  cross-region fetch and self-correct; zero cuts the region off.

Everything below the role — the feed, the region-keyed watermarks carried as
feed rows, the pass-start buffer — is identical to the managed path. What is missing is the authority: no primary designation, so "complement
of the primary" does not apply; no rollout orchestrator, so no caught-up
gating on promotion. Role changes are more frequent and less ordered, and the
region watermark (§4.3) is what keeps them cheap.

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
  family. **Value**: the same descriptor the backfill listing already carries
  — `kind`, `record_id`, `version_ms`, `size` — plus `arrived_at_ms`, the
  commit's wall-clock time, so lag can be reported in seconds as well as rows.
  About 100 bytes. The manifest itself (producer, namespace, key, content
  type, branch, trunk) is not in the row: it arrives with the body, in the
  frame `meta` the bodies endpoint already sends. One row per *change*, not
  per live artifact; namespace deletes are rows like any other, so the sibling
  link carries them losslessly, and so are the region-watermark advances of
  §4.3.
- **`seq`** comes from a persisted per-node counter, monotonic across restarts
  and independent of any wall clock. The row is written in the same batch as
  the change it describes, so a crash cannot separate them.
- **A position is `(incarnation, seq)`.** The incarnation is a random id the
  node mints once, the first time it creates its store, and persists in it
  (`sync/meta/incarnation`). It identifies *that copy of the data*, not
  the node: a restart on the same volume keeps it, a pod recreated on an empty
  volume gets a new one. Every forward response echoes it and the puller
  stores it beside its cursor, the way a Kafka consumer keeps the cluster id
  with its offset. Without it `seq` is ambiguous — a rebuilt store restarts
  the counter at zero, so a sibling holding an old, higher cursor would sit
  above the new head and long-poll forever, never falling off the feed. The
  request carries it — `after={incarnation}:{seq}` — because the source cannot
  otherwise tell a foreign cursor from a future one. This is a routine event,
  not only a node move: the controller rebuilds a data volume one ordinal at a
  time behind the standby whenever an account's claim grows (#12947), and each
  rebuild is a new incarnation that bootstraps from its sibling. It is not the
  `generation` in `/ready`, which is per-process cluster state.
- **Written for what the sibling does not have.** A client write and a
  region-sync apply each produce a row. A change that *arrived from the
  sibling* — by either sync direction, or by an old-version sibling's push
  during migration — never does: its only consumer already has it, and without
  this rule the two replicas would echo every record back and forth forever.
  Nor does an apply that changed nothing (last-writer-wins kept the local
  record). A push received on the legacy routes *does* earn a row: it names
  no region and may have crossed a boundary, so it is treated as
  cross-region. That cannot loop — an apply that arrived over the feed writes
  no row on the receiving side, and a same-region old-binary pusher never
  reads the feed, which is off until a pulling sibling asks. In a two-replica
  region the row is never even written; with more replicas it costs one
  redundant delivery that last-writer-wins absorbs (D-1).
- **Activated by its consumer.** The feed is off until a same-region peer's
  first `{head}` request, which switches it on and returns the head in the
  same operation — activation and snapshot are one event, so there is no
  window in which rows go unwritten between a sibling's snapshot and its
  forward read. It stays on while the peer list names a sibling, and turns
  off, dropping its rows, once no sibling has been listed for longer than
  the mesh's stale-peer window. A region of one therefore carries no feed at
  all. Activation is persisted (`sync/meta/enabled`), so a restart brings the
  feed back as it was instead of silently switching it off under a sibling
  still reading forward; deactivation after the stale window clears it
  (D-10).
- **Trimmed from below.** Every request carries the sibling's cursor, and the
  source deletes rows at or below it in a batched trim — with one consumer per
  direction, that position is a single number. Trims are range deletes and
  the floor is kept as an explicit meta value, not found by iterating: a feed
  that churns at its cap would otherwise leave a wall of point tombstones for
  every seek to the floor to climb.
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
  is sub-millisecond on loopback. Each forward page is applied as one
  backfill pass — claim set, byte-bounded bodies batches, group commits, all
  reused as they are — and the cursor advances when that pass completes.
  Fetching page N+1 while page N applies is lost; pages are small on a
  long-poll link and a catching-up sibling is bounded by loopback, so the
  simplicity wins, and pipelining across pages is the first optimisation to
  revisit if the lag gauge says otherwise (D-9).

The endpoint is
`GET /_internal/sync/forward?peer={url}&region={region}&after={inc}:{seq}&wait=25s`,
under the same peer authentication as every other `/_internal/*` route. The
request names the requester: `region` is checked, because the feed is
intra-region only, and `peer` keys the consumer cursor that trimming and the
drain gate read (D-3). The contract is four cases, plus one the
implementation added:

- **`after` at or above the floor** — returns `{entries, next, head}`,
  blocking up to `wait` when nothing is above the cursor, so a sibling
  converges in milliseconds without polling. `head` is the source's newest
  seq; `head - next` is the sibling's lag in rows.
- **`after` omitted** — returns `{head}` immediately, with no entries. This is
  the snapshot a bootstrapping sibling takes before its backward pass.
- **`after` below the floor** — `410 Gone` with `{floor, head}`. The rows
  between were dropped; the sibling has fallen off the feed.
- **`after` from another incarnation** — the same `410`. The cursor names a
  store that no longer exists.
- **`after` above the head** — the same `410`, reason `ahead`. Rows are
  visible to the sibling before the WAL fsync that makes them durable, so a
  crash can lose a tail the sibling already consumed and restart the counter
  below its cursor. Rather than track durability per row, the source treats
  any cursor above its head as foreign; the sibling re-bootstraps, and the
  backward pass covers the lost tail (D-2).

The `{head}` response also carries the region watermark map of §4.3. The
puller adopts it only when the backward pass that follows completes — by then
it holds everything the map's positions vouch for — and from there on advances
arrive as feed rows, in commit order, like everything else.

The puller **advances its cursor only when every entry of a page is applied or
resolved** — resolved meaning the body came back `Absent` because the source
evicted it in between, which is legal. A page that fails part-way is retried
whole; re-applying is idempotent under last-writer-wins.

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

The strand grace window does not go away with the lane: a backward pass is
newest-first, which is entry-before-blobs by construction, so a young entry
whose blobs are still arriving remains a normal condition. What changes is
that its safety no longer rests on the window's length — the serve-side gate
below covers the case however long the blobs take.

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

The check is bounded to where it can bite. An entry older than the strand
grace window has already been through the action-cache cascade, which removes
entries whose blobs were evicted, so only entries *younger* than the window
are checked at serve time. The cost is one manifest point lookup per
referenced blob, on young entries only — microseconds against cached blocks,
and zero for the steady-state hit. This needed no new code: `GetActionResult`
already inspects every referenced blob's presence before answering (the
composite presence gate #12937 extended to chunk recipes), answers `not_found`
when one is gone, and deletes the entry only past the cascade grace window
(D-17).

Content-defined chunking (#12937) already works this way, and is the second
dependency class the gate covers. A recipe under `blob_chunks/{hash}/{size}`
references its chunks the way an action-cache entry references its blobs, and
it keeps its creation `version_ms` rather than being stamped behind them:
backfill can encounter the recipe before its chunks, and "the composite
presence and read gates keep it unavailable until every dependency arrives".
That is INV-6 for recipes, already shipped. The consequences carry over
unchanged. Recipes are classified with the capacity-sensitive records in the
index, so the ascending read's per-entry capacity rule (§4.1) declines them
with their chunks. And a recipe that reuses chunks older than the puller's
horizon — the normal case for an incremental build — is an honest miss where
the chunks are absent, which the client repairs by design: a miss on the
logical blob makes Bazel probe the chunks, upload the missing ones and
re-splice, and the bounded expiry sweep reclaims the stranded recipe.

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
The gate runs before the internal listener stops accepting — the e2e drain
scenario caught the other order, in which the sibling could never report the
cursor the gate was waiting for — and long-polls are held for at most 250 ms
while draining, so the sibling re-asks at once with its new cursor.

Three cases are decided rather than left to the implementer. A region of one
has no sibling and exits at once. A sibling that has not yet taken a forward
cursor — it is mid-bootstrap — is not waited for, since its backward pass
resumes against the recreated pod's persistent volume; its `{head}` snapshot
still pins the feed's trim floor, so the rows above it survive the pass, and
only the drain gate ignores it (D-13). And the grace period
the wait is bounded by is a Helm value, so the change ships with the matching
`terminationGracePeriodSeconds` in `ops/`, as the rollout rules require.

An expiry is a counted event, not a loss: the feed is on the persistent
volume, so the recreated pod serves the tail when it comes back and the
sibling merely lags for the restart. The one genuine loss is a node move on
local-path storage, where the volume itself is gone — which is the pre-existing
loss of that storage class, not something this design introduces. The
controller's volume rebuild for a grown claim (#12947) is this sequence by
construction — the ordinal is replaced behind its sibling, drains, comes back
on an empty volume and bootstraps — so §3.6 is also what that path should
wait on before moving to the next ordinal.

### 3.6 Readiness follows the sibling, never the region

`/ready` latches when the replica bootstrap settles: the backward pass against
the sibling completed and the forward cursor is within one page of the
sibling's head. The link settles the moment its bootstrap completes: the
cursor then sits at the snapshot head, within one page by construction, and
waiting for the first forward page would hold readiness for up to one
long-poll wait with nothing to show for it (D-19). Without a sibling it settles immediately; with a sibling that
cannot be reached it settles when the pass exhausts the failure budget the
backfill already has, ready-but-cold exactly as today; and the existing
ring-fullness latch is kept as the cold-but-useful escape it is. The budget
is charged per peer, not per link task: a sibling that flaps through the
membership view has its link cancelled and reopened each time, and a count
that restarted with the task could hold readiness open for as long as the
flapping lasts, where the legacy cycle charges the peer once (D-23).

With a sibling present, region sync never gates readiness, and neither does
the gateway role: both are best-effort by requirement, and a replica that has
never been gateway is no less able to serve. A **region of one** has no
sibling to be warm from, so for it the initial backward passes over the remote
gateways gate readiness exactly as today's initial cycle does, with the same
ring-fullness escape. Readiness means one thing: serving from this node will
not cost hits that a warm source would have served.

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
  **It lists only the records the serving region originated.** Every manifest
  carries `origin_region`, stamped at first write and carried through
  replication as an additive field (an old peer drops it; a record with no
  origin is listed by everyone, which is the migration fallback). A region's
  writes therefore reach every other region from that region's gateway and
  from nowhere else: each record's descriptor crosses `R-1` links instead of
  `R(R-1)`, a gateway's cross-region egress is exactly its own region's
  writes, and each region's watermark lives in that region's clock (§4.6).
  Backward passes stay unfiltered — a cold fill wants everything, newest
  first, from whoever holds it. That is also what makes a *departed* origin
  harmless: after a relocation (#12956) nobody lists that region's records
  forward, but every backward pass still delivers them from whichever gateway
  holds them. The origin filter is a manifest lookup per row (manifest cache
  first), not a field in the index row: the `backfill/idx/` value is exactly
  eight bytes and an older binary rejects any other length, so widening it
  would break the listing under rollback. The cost is bounded by the page and
  paid only by forward region reads (D-5).

On a full ring the ascending read applies the marginal trade
`capacity_complete` already makes, per entry: an entry older than the next
evictee's stat is **declined** — counted as observed, so the watermark still
advances, but not fetched, since fetching it would rotate out something
newer. Descending passes stop at that point; ascending ones pass through it
into the range that is worth fetching.

Long-polling applies here too — the forward read blocks until the peer has rows
above the watermark — so cross-region convergence is bounded by transfer time
rather than by a poll interval. The maximum blocking window is the same 25
seconds as the replica link (D-8); a failed read retries on the backoff the backfill
already uses (250 ms doubling to 5 s). Every listing response carries the
peer's `now`, a new field on `/_internal/backfill/entries`.

The ascending read also carries a settle guard. A record's `version_ms` is
stamped before its batch commits, and batches commit in any order, so a puller
that lists up to the newest committed entry could skip a lower entry whose
batch is still landing. The serving node therefore never lists an entry
younger than `now − KURA_SYNC_REGION_SETTLE_MS` (default 2 s) — the ascending
read's equivalent of the feed's contiguous head (D-6).

**The page cursor is the full index key, the watermark is only its
`version_ms`.** `version_ms` has millisecond granularity and a busy region
writes many records in a millisecond, so a cursor that were the bare watermark
would either skip the rest of a tie or re-list a tie larger than a page
forever. `/_internal/backfill/entries` already pages by the full key as an
opaque `after`; the ascending read does the same. Within a connection the
cursor is that key; what is persisted and shared (§4.3) is the `version_ms` of
the last consumed entry, and a resume from a watermark alone starts at
`(watermark, "")` inclusive — re-listing at most one millisecond's worth of
entries, which are skipped as already present. The ascending page carries
its cursor whenever the scan moved, full or not, so a caught-up requester
keeps continuing from it across long-polls and resumes from the watermark
only after a failure; a page with neither entries nor cursor is the
caught-up signal the server's long-poll waits on (D-14).

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
- **One per origin region, advanced only by that region's records.** A single
  global watermark would skip records: if you pulled everything at or above T
  from one region and advanced past T, records at or above T that only another
  region holds are never requested. Keyed by *origin* region rather than by
  the node currently holding its gateway, because the remote role moves on
  every one of its deploys: a node-keyed watermark would start from nothing
  each time and cost a full horizon-bounded pass, in every region, per remote
  deploy. Region-keyed is sound for the same reason §4.3 gives — the remote
  replicas are lossless siblings, so what the old gateway had shown, the new
  one holds — and a remote role move is just "a gateway entering", which runs
  the buffered backward pass of §4.4 against the new node. Advanced by origin
  because a backward pass lists everything a gateway holds, other regions'
  records included; only entries the watermark's own region originated move
  it.
- **Advance contiguously.** "Observed" and "consumed" are one rule: the
  watermark takes the highest `version_ms` shown in a page once that page is
  consumed — every entry applied, declined or resolved `Absent`. Because the
  forward read is ascending, the watermark
  moves to the last entry consumed without a gap behind it. A read that fails
  part-way keeps whatever contiguous prefix it consumed and resumes there. The
  backward pass keeps the stricter rule — it lists descending, so it advances
  its watermark only on completing the pass. On completion it advances to
  the serving gateway's clock at pass start, less the buffer: the listing
  carries no origin per row, so the highest own-origin `version_ms` shown is
  not observable, while the gateway's `now` is that region's clock domain
  and `now − buffer` is below anything still in flight to it (D-12).

### 4.3 The watermark is region state, replicated between replicas

Carry watermark advances **as feed rows** — kind `watermark`, value
`{origin_region, version_ms}`, one per cross-region page the gateway consumes
— and **merge by max** on apply. The sibling then adopts each advance in
commit order, after the rows for the records that earned it, so it never
holds a position it has not yet covered: a watermark taken from a page
envelope would be adopted the moment the page arrived, ahead of the feed rows
behind it, and a gateway whose volume was then lost would leave its sibling
claiming coverage it never received. Both replicas hold the region's current
position, so a promoted gateway starts from where the region actually is, and
a demoted one does not sit on a stale value. A cold node gets the whole map
with its `{head}` snapshot and adopts it when its backward pass completes
(§3.1).

This is sound *because replica sync is lossless*. Adopting the sibling's
watermark asserts something about your own coverage, which is the objection that
sank earlier cursor-inheritance schemes — but here anything the gateway acquired
below the watermark reaches its sibling over the sibling link regardless. That
link is the delivery path; the cross-region one is not. The strict intra-region
guarantee is exactly what licenses the loose inter-region sharing.

Entries are never dropped: a region that leaves the peer list keeps its
watermark, so a return — or a transient disappearance — resumes rather than
restarts, and the cost is a few dozen bytes per region a mesh has ever seen.

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

Continuous forward reads use the watermark directly. A region's writes reach
its gateway over loopback in near-`version_ms` order, and only that gateway
lists them (§4.1), so the forward read's only exposure is the origin region's
own intra-region lag. Relay through a third region is not relied on — and
would not work on an ascending read, since a record arriving late at a third
gateway sorts below the puller's watermark there. A stalled pair loses nothing
while it lasts: the puller's watermark on the stalled region freezes, and the
forward read resumes from it when the path heals.

A backward pass that *starts* — discovery, restart, promotion — widens its bound
instead:

```rust
min_version_ms: horizon.max(peer_watermark_ms - buffer)
```

The horizon **floors** it, so the buffer can never push the pass below the
horizon however large it is set. It is self-limiting, which makes choosing the
value low-stakes: pick generously and the horizon caps the work. This is a
one-line change to `compute_window`, not a new pass type.

The buffer has to cover the origin region's own lag when the watermark last
advanced — a write landing on the primary and reaching the gateway over the
feed — and the long tail of that is the origin's rollout: a restart, a drain
gate that expired, a sibling mid-bootstrap. Minutes, not clock drift. The
default is therefore **10 minutes**, replacing the 60-second skew allowance
the walker carries today for the same slot. The cost of a generous value is
listing, not fetching: ten minutes of a busy region's writes is a few thousand
~100-byte rows, presence-checked and skipped.

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
by it. Because each watermark belongs to one origin region and only that
region's records advance it (§4.2), and only that region's gateway lists them
(§4.1), a watermark lives entirely in its region's clock domain: skew between
regions cannot push a watermark past records another region is still
writing. What skew still decides is what it decides today — last-writer-wins
between two regions writing the same key — and the intra-region link never
consults a clock at all.

The residual requirement is inside a region, where both replicas stamp
writes during the drain overlap: their clocks must agree within the buffer,
which NTP on co-located pods makes trivial. Every listing response carries the
peer's `now`; the puller exports the difference as
`kura_peer_clock_skew_seconds{peer}` and alerts above the buffer, so a
misconfigured self-hosted clock shows up as a named cause before it becomes
an unexplained conflict rate.

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

### 5.2 Ship, flip, remove

Three steps, of which only the middle one changes behaviour.

- **Ship.** The binary carries everything and does nothing new with it: the
  arrival feed under a new key prefix in an existing column family (never a
  new CF — the store opens with an explicit descriptor list, so a rollback to
  a binary that does not know the CF fails to open the database),
  `GET /_internal/sync/forward`, the ascending read and `now` on the existing
  listing, `origin_region` stamped on new manifests. The server publishes
  `peer_roles` beside `peers`; older nodes ignore a field they do not know.
  Push still does all the work. Its depth cap is already per target (#12826),
  which is what lets links that stay on push through the whole support window
  survive a dead peer; what that share cannot do — stop a write being refused
  because one of its targets is full — is what the flip removes.
- **Flip.** One flag per account, rendered into each instance's spec from the
  account's feature flag and published in that mesh's roles. A node with the
  flag on **advertises that it is pulling**, and applies one rule per peer:

  > If the peer advertises pulling: stop pushing to it, and pull from it if my
  > role says so — from every pulling peer, with region-keyed watermarks, while
  > I have no roles yet. Otherwise push to it and accept its pushes, exactly
  > as today.

  The capability has to mean *I am pulling from you*, not *I can serve a
  feed*; with the weaker meaning a flag-on node would stop pushing to a
  flag-off peer that serves a feed but never asks, and that peer would
  silently stop receiving. With the stronger one the handshake is symmetric
  per pair, and a flag-off node — or a rolled-back binary — simply keeps being
  pushed to.

  Narrowing to roles does not wait for every peer to be capable. An old peer
  cannot pull, so a pulling node keeps pushing to it in both directions, and
  since receivers never forward, a non-gateway's own writes still reach old
  peers by its own push. A mixed mesh is correct throughout, merely redundant.
  Which pull a pair uses follows `region`: same-region pairs use the feed,
  every other pair the `version_ms` reads with a region-keyed watermark. A
  node that starts pulling from a peer bootstraps as §3.1 describes —
  snapshot, backward pass, forward — so the moment the pusher stops is covered
  by the pass. Reverting the flag is the same handover in reverse: the outbox
  has no rows for the window pull was active, so a revert arms one backward
  pass per peer before push resumes.

  One exception to the rule above, stated in full in §11.2: a peer that
  advertises pulling but whose own membership view does not name this node
  cannot dial back, so pull would reach it in neither direction and it stays
  a push target until its view names us.

  Two rules the code and the lab added. The legacy scheduler steps aside *per
  peer*: peers that advertise pulling leave the backfill lifecycle's view
  (never passed over, never part of its initial cycle) while this node pulls,
  peers that do not keep today's passes and pushes, and readiness combines
  both — the legacy cycle settled *and* the pull links settled (§3.6), or the
  ring-fullness escape (D-16). And a peer's pull flag is remembered while it
  is unreachable: the push targets are rebuilt from the membership view, and
  a pulling peer that stops answering its status probe leaves the view, which
  read as "not pulling" and put it back on push, queueing an outbox row per
  write for as long as it was down. A node now keeps the set of peers that
  last advertised pulling (in memory, like the discovered-only history) and
  keeps them off the push targets until they come back saying otherwise; a
  rolled-back peer that returns with `pulling: false` is pushed to again from
  its next tick (D-20).
- **Remove.** Delete the outbox code once no account has a non-pulling peer.
  `ROCKSDB_CF_OUTBOX` stays, empty, for the same reason no CF is ever added —
  a binary that expects it must still open the store.

The region watermarks live under a new prefix, `sync/wm/{region}`, seeded on
first use from the highest of the old per-peer `backfill/wm/` rows for that
region's nodes — or the horizon when there are none — and the old rows are
left for the rolled-back binary that still reads them. The seed is taken
lazily, by the region task, the first time it needs a watermark it does not
have (D-4).

What the single flip gives up is the window in which pull could be watched
running while push still did the work. The per-account flag replaces it: flip
one account, watch the §6 metrics, flip the rest. Three things about that
flag are easy to get wrong: it has to be part of what bumps the instance's
`manifest_revision`, or the reconciler never deploys the new spec; it must
not be a new CRD field, which fails every rollout bump until the CRD is
upgraded; and the `terminationGracePeriodSeconds` change for §3.5 has to
land on an account *before* its flip, not with it. The first account should
not be the only model: a mesh with a self-hosted peer is what exercises the
per-pair rule for longer than a rollout window.

### 5.3 The constraint that decides the timeline

**Removal is gated by the oldest self-hosted version still in the field, not by
our own rollout.** A self-hosted peer that never upgrades keeps every link
touching it on push, so the outbox has to stay compiled in — and its depth cap
keeps applying to those links — until the supported-version floor moves past
the shipped binary. Plan for the outbox living alongside the new path for at
least one support window, and make sure the metrics distinguish the two so the
remaining push traffic is visible rather than assumed gone.

---

## 6. Observability

Per `kura/AGENTS.md`, every metric added or changed here needs a matching panel
in `infra/grafana-dashboards/tuist-kura-details.json`, with the operational
interpretation in the panel description rather than the Prometheus HELP text.
Counters scrape with a doubled suffix (`foo_total` is served as
`foo_total_total`), so panels must query the scraped name. Series cost is per
pod times labels (#12969 dropped every histogram bucket family no alert
reads, at ~750 series per two-replica instance): nothing below adds a
bucket family, the one duration is exported as `_sum` and `_count`, and the
labels are bounded — `region` by the plan's region count, `peer` by one
sibling. The panels are the "Pull replication" row of that dashboard; the
names below are the shipped ones.

### 6.1 Retained, retired, reframed

| Metric | Fate |
| --- | --- |
| `kura_outbox_messages`, `kura_outbox_lane_messages`, `kura_outbox_target_messages{target}`, `kura_outbox_peer_capacity`, `kura_outbox_capacity` | Keep until removal — they measure the remaining push traffic, which is exactly what tells you whether removal is reachable. Retire with the outbox. |
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

- `kura_sync_forward_fell_behind_total{reason="floor|incarnation|ahead"}` —
  the puller's side of the same event: a `410` received. One per drop event is
  expected; a climb during recovery means the cap is smaller than the sizing
  rule requires. `incarnation` names a sibling rebuilt on an empty volume;
  `ahead` a cursor above the sibling's head after a crash lost an unsynced
  tail (D-2).
- `kura_sync_forward_drain_timeout_total` — a departing node exited before the
  sibling reached its head (§3.5). Recent writes lagged for the restart.
- `kura_sync_pull_links{link="replica|region"}` — open pull links by kind. A
  gateway holds one region link per remote region plus its replica links; a
  non-gateway holds replica links only, so a region link on a non-gateway is
  INV-4 violated.

**Region sync**

- `kura_region_sync_last_success_age_seconds{region}` — time since the last
  successful forward read from that region, empty reads included. The primary
  inter-region health signal (§2.2).
- `kura_region_watermark_age_seconds{region}` — lag, meaningful while the
  remote region is writing; not a health signal on its own.
- `kura_region_sync_last_cycle_duration_seconds`, `_entries_listed_total`,
  `_bytes_fetched_total{region}` — cost and progress per cycle.
- `kura_peer_clock_skew_seconds{peer}` — peer `now` minus local `now` from
  each listing response (§4.6).

**Topology**

- `kura_gateway_role{state="gateway|standby"}` — one series per node, so a
  region with zero or two gateways is visible directly.
- `kura_gateway_role_changes_total` — churn; a step change after a deploy is
  expected, a continuous climb is not.

### 6.3 Alerts

| Alert | Condition | Why it matters |
| --- | --- | --- |
| Gateway cut off | `kura_region_sync_last_success_age_seconds` above 5 min for every remote region | The region's WAN path is broken, or the pod's sync loop is wedged; a restart resolves the second, nothing but the network the first (§2.2) |
| Region pair stalled | the same, for one remote region only | The path between two regions is stuck; nothing is lost while it lasts (§4.4), but the pair is not converging |
| Region without a gateway | no series with `state="gateway"` for a region beyond the transient window | INV-3 violated |
| Sibling fell off the feed | `kura_sync_forward_index_dropped_total` increases | Loopback should never be slow enough for this |
| Drain gate expired | `kura_sync_forward_drain_timeout_total` increases | Recent writes lagged for a restart; the sibling was down or the grace period is too short |
| Clock skew above the buffer | `kura_peer_clock_skew_seconds` beyond 10 min | The slow region's writes are a standing inter-region miss until fixed (§4.6) |
| Push traffic not declining | `kura_outbox_messages` non-zero on links expected to have migrated | A flipped account still has a peer on push, or the flip did not deploy |

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
than transiently while the holder restarts. Two gateways during a transition cost one duplicate transfer and
self-correct; zero cuts the region off.

**INV-4 — a node talks only to the peers its role names.** Among pulling
peers (§5.2); a peer that cannot pull is pushed to as today. Non-gateways
never open a cross-region link to a pulling peer. A stuck cross-region path is an
alert (§2.2), not something to route around — the exception being the serverless
self-hosted mode, where the node derives its own role because there is no
authority.

**INV-5 — never designate a gateway that is about to be drained.** The role
would evaporate seconds later; and a bare "complement of the primary" rule hands
it to exactly that pod when serving flips (§2.1).

**INV-6 — do not serve an action-cache entry whose referenced blobs are
absent.** This, not delivery ordering, is what makes divergence produce a miss
rather than a broken build.

**INV-7 — the arrival feed is trimmed and capped, never allowed to block a
write.** Dropping the oldest rows is correct; refusing a write because the feed
is full is the failure this design exists to remove.

**INV-8 — `delete_everything` (`version_ms == 0`) stays node-local.** It writes
no tombstone and enqueues nothing today, and must not acquire replication state
either.

**INV-9 — eviction never propagates.** Every node evicts under its own
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
holds one row per *unconsumed change*: at ~100 B a row — the listing
descriptor plus an arrival stamp, never the manifest — the default cap of one
million rows is about 100 MB logical, ~80 MB on disk, independent of how many
artifacts the node holds. With a sibling pulling over loopback the steady-state
depth is near zero, and a region of one carries no feed at all (§3.1), so the
cap is a ceiling reached only while a sibling is down.

Memory follows from that. The feed's index blocks are proportional to its
retained size, not to the artifact count, so they are a fraction of a MB at any
sensible cap. Two things still matter:

- **Issue sync reads with `fill_cache = false`.** Every iterator is built with
  default `ReadOptions` today, so `fill_cache = true`; a cursor scan reads each
  block once, and caching those blocks is pure eviction pressure on the manifest
  blocks the read hot path needs. This also fixes the same pollution in the
  existing backfill listing.
- **The write path gets cheaper in bandwidth, not latency.** One feed row per
  commit replaces `N-1` outbox rows in the synchronous batch, plus their later
  deletes — on a six-node mesh roughly 1.8 KB of routing state per small write
  becomes 0.1 KB, and the feed's own deletes are batched range trims rather
  than one point delete per delivery. The batch still fsyncs once, so p50 write
  latency moves little; what goes is WAL and compaction bandwidth, the slot
  reservation, and the `429` path.
- **The sender's transient memory goes.** Today the pusher holds up to 32
  in-flight bodies (512 KiB chunks, or whole inline entries up to 4 MiB) plus
  metadata batches of up to 8 MiB each — tens to a few hundred MB on the
  write-hot node under burst. Pull streams bodies from segment files under the
  existing response-memory controller; the puller's standing cost is one
  descriptor page and claim queue per link, low single-digit MB per gateway.
- **The serve-side gate (INV-6) costs one point lookup per referenced blob, on
  entries younger than the strand grace window only.** Older entries are
  covered by the cascade and pay nothing.

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
middleware, and clean handling of the internal plane's connection lifecycle. If a persistent
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

**Suspending the gateway role for the duration of a rollout**, with an expiry,
a per-mesh cap and an alert. It existed to avoid the four role moves a deploy
causes. But a move costs one duplicate listing and a brief pause (§2.1), the
Ready-and-non-draining rule already keeps a draining pod from being designated
(INV-5), and suspension pauses the region's cross-region sync in *both*
directions for the whole deploy — which is worse than the churn it avoids, and
needed a timeout, a cap and an alert to be safe.

**Automatic re-designation on read staleness.** The replicas of a region share
a host and therefore a WAN path, so the failure the rule detects is one a role
move cannot fix; the one it can — a wedged sync loop in a Ready pod — is fixed
by a restart. With the decision gone, so are its cooldown and its flapping
case. The signal and the alerts stay (§2.2).

**A node-side bypass of a lagging gateway.** The failure it addresses —
unreachable gateway — is already handled by the server's designation rules,
and the one case those miss (Ready and heartbeating, WAN broken) is shared by
both replicas of the region, so no node-side choice fixes it either; it is an
alert. A bypass would put topology decisions in two places at once. §2.2.

**GossipSub (libp2p pubsub) as the inter-region forward link.** Proposed in
review as a sparse alternative to the gateway clique. Transport is not the
objection: a spike showed a libp2p PeerId derives identically from the
enrolled P-256 certificate on both sides, and that a third ALPN value on the
7443 mTLS listener demuxes cleanly with old binaries failing over to HTTP in
under a millisecond. It is rejected on semantics. GossipSub is a live event
stream with about five seconds of memory (a message cache of five heartbeats),
no position, no durable state and no queue, so a delivery can never advance
the region watermark without violating INV-1 and INV-2; either the ascending
listing keeps running to move the watermark (and gossip only adds bytes,
since the long-poll already wakes on commit) or the watermark moves only on
backward passes, and every gap longer than the cache, plus a timer for silent
loss, costs an unfiltered backward pass against every remote gateway from a
watermark as old as the last pass. Deletes ride the same stream, so a missed
tombstone leaves a namespace servable until the next pass. A subscription
dies with its connections, so a gateway flip either keeps both replicas
subscribed permanently or re-bootstraps on every move. At the mesh degree of
six every gateway is in every other gateway's mesh, so it floods exactly as
the clique does until the region count exceeds about five. It brings around
190 crates with a second crypto stack, connections outside the listener's
drain accounting, and a PeerId that changes on every certificate rotation
unless enrollment stops regenerating the key; and the listing has to stay as
the fallback for every pair because self-hosted meshes upgrade on their own
schedule. Its one genuine advantage, symmetric connections, covers the
runner-region case in §11.2; that case is handled there without it. §4.1,
§4.2, §4.7.

**Multi-source (multi-holder) body fetch between regions.** Proposed with
GossipSub, as a way to spread a busy origin's upload. The gateway is the
standby, so the only resource it can saturate is its egress class; when it
does, the other gateways receive `503` with `Retry-After` or a slow stream,
back off and retry, and nothing is lost because the record stays in the
listing and the watermark does not move past it. Convergence slows, which
inter-region best effort permits. Fetching the same bytes from another region
moves the egress to that region's bill and leaves total WAN bytes at
`(R-1) x S`; with at most `R-1` downloaders per record the swarm case never
arises, a downed gateway is covered by its sibling taking the role, and the
multi-gigabyte tail is a resume-by-range problem on the same source. The lever
for a region whose class caps its convergence is the class or the writer's
placement, not more sources. §11.1, §11.3.

---

## 10. Parameters

Every value the design depends on, with its default and the rule that chose
it. They are configuration with defaults, not open questions; the rule is what
to re-check when a measurement disagrees.

| Parameter | Default | Rule |
| --- | --- | --- |
| Pass-start buffer (§4.4) — `KURA_SYNC_PASS_START_BUFFER_MS` | 10 min | Covers the origin region's own lag when the watermark last advanced; the tail is that region's rollout. Cost is listing only, horizon-floored. Re-check against the observed distribution of (arrival at the origin's gateway − `version_ms`). |
| Feed cap (§3.1) — `KURA_SYNC_FEED_MAX_ROWS` | 1,000,000 rows (~100 MB) | Must hold the writes that land during the longest backward pass a sibling can need, or recovery loops. Re-check against peak write rate × cold-pass duration. |
| Long-poll wait (§3.1, §4.1) — `KURA_SYNC_LONG_POLL_SECS` | 25 s | Below the peer client's 30 s idle read timeout, which every internal request shares — a 30 s hold would race it (D-8). Idle polls re-check every second, bounding a missed wake; the ceiling is 60 s. Bounds how long a cleanly idle link goes without a proof of life. |
| Settle guard on ascending reads (§4.1) — `KURA_SYNC_REGION_SETTLE_MS` | 2 s | The serving node never lists an entry younger than this: batches commit in any order after their `version_ms` is stamped, and a lower entry still landing would be skipped by a puller that read past it (D-6). Re-check against the observed commit latency under load. |
| Feed stale-peer window (§3.1) — `KURA_SYNC_FEED_STALE_PEER_SECS` | 30 min | The feed turns off, dropping its rows, once no sibling has asked for this long; the mesh's own stale-peer window, so a sibling that is merely restarting never loses its feed. |
| Drain margin (§3.5) — `KURA_SYNC_DRAIN_MARGIN_MS` | 5 s | Subtracted from the termination grace period to leave the process time to exit cleanly after the gate; the gate itself is the drain wait below. |
| The flip (§5.2) — `KURA_REPLICATION_PULL`, account flag `kura_replication_pull` | off | Per node by env, per account by the server flag rendered into each managed instance's spec and its manifest revision, so the flip rolls; either source makes the node advertise `pulling`. |
| Peer bodies slots per peer (§11.1) — `KURA_SYNC_PEER_BODIES_SLOTS_PER_PEER` | 1 | What one peer identity may hold in flight on the serving side. One is what the requester already asks for; the value exists so a mesh whose links are latency-bound can widen it deliberately rather than by patch. Re-check against the observed `rejected_busy` rate on a gateway. |
| Peer serving aggregate (§11.1) — `KURA_SYNC_PEER_SERVING_MAX_INFLIGHT` | derived: `max(8, visible peers × slots per peer)` | Bodies requests one node serves across every peer identity, re-derived on every membership tick so every counted peer can hold its slots; the floor of 8 covers requesters the view does not count (a peer a tick ahead of it, or one that cannot be dialled back). Setting the variable pins it. Rejection, never a queue. Re-check against the `rejected_node_busy` rate. |
| Retry backoff after a failed read (§4.1) | 250 ms → 5 s | The backfill's existing constants. |
| Staleness alert threshold (§2.2) | 5 min | Ten consecutive failed long-polls; short enough to matter, long enough that a slow transfer is not a failure. |
| Overlap window on a role move (§2.2) | 2 heartbeat periods | Long enough for every node to have fetched the new list; costs one duplicate listing. |
| Readiness lag (§3.6) | one page of the sibling's head | Caught up for every purpose that costs a hit. |
| Drain wait (§3.5) | termination grace period − margin | The wait is normally zero; the bound is the pod's, not a new one. |
| Clock skew alert (§4.6) | above the buffer | Inside a region the drain overlap depends on it; between regions it only decides last-writer-wins, as today. |
| Serve-side gate age (§3.3) | the strand grace window | Older entries are covered by the cascade; the existing constant, not a new one. |

---

## 11. Follow-ups on this branch, and one future extension

All on the same plane: none changes the endpoints, the identity or the
migration rule. §11.1 and §11.2 are part of this design and ship on the pull
replication branch before any account flips; §11.3 is gated on the trigger
stated with it.

### 11.1 Hard upload limits, made explicit

Most of the serving-side protection exists: one bodies request in flight per
peer identity, answered `503 peer_busy` with `Retry-After` and counted as
`rejected_busy`; response streams charged to the background memory budget and
shed with `503` under pressure; the adaptive bandwidth ceiling shared across
peer uploads, ingests and fetches; the per-tenant HTB egress classes below the
process. What is implicit becomes configuration: the per-peer bodies slot
count and a per-node aggregate on peer-serving concurrency, the aggregate
derived from the membership view as `max(8, visible peers × slots per peer)`
unless pinned by configuration. Rejection stays
the behaviour, never a queue, so a receiver can back off or skip. The
`rejected_busy` rate and the limiter's effective rate join the pull
replication dashboard row, so concentration on one gateway is measured
rather than argued. Ships on the branch (implementation log T9.1).

### 11.2 Co-located instances that other nodes cannot dial

The runner-cache region publishes no public peer host, so an enrolled
self-hosted node never lists it as a peer and cannot dial it, while the
runner node dials the self-hosted node from its static peer list. Today push
covers that leg. After the flip the runner node sees the self-hosted peer
advertise `pulling`, stops pushing to it and opens a region link *from* it,
and nothing pulls the other way: the runner region's writes reach that
self-hosted node only through backward passes from other managed gateways.

The rule: **a node keeps pushing to a pulling peer that does not know it.**
Every node already advertises `pulling` in `/_internal/status`; it also
advertises the node URLs of its membership view. A pusher takes a pulling
peer off its push targets only once that peer's advertised view names the
pusher's own URL; until then, and whenever the view stops naming it, the peer
is pushed to as a non-pulling peer would be. The rule is decided from what
the two nodes already exchange, so it needs no server field, works under a
self-hosted server and in the serverless mode, and errs toward duplicate
delivery (a push into a node that is also pulling the same records is
absorbed by last-writer-wins and earns one feed row, D-1) rather than toward
a silent gap. The runner region's node therefore keeps pushing to every
self-hosted node for as long as those nodes cannot list it, and stops on its
own the day the region gains a public peer host. Ships on the branch with a
ring-A test and a ring-B scenario (implementation log T9.2).

### 11.3 A Plumtree-shaped tree, if the clique or egress spread ever matters

Trigger: more than about five regions in one mesh, or one origin's gateway
sustained near its egress class. The shape is Plumtree's eager/lazy split
(Leitão, Pereira, Rodrigues, 2007), composed with this design rather than
replacing it:

- **Lazy links stay as they are.** Every gateway keeps reading each origin's
  listing ascending from its watermark. Descriptors are about 100 bytes; this
  is what advances the watermark and what keeps tombstones and recovery
  complete. The watermark, the backward pass and the roles do not change.
- **Eager links carry bodies.** A gateway fetches bodies from one parent that
  already holds them instead of from the origin: a non-origin gateway serves
  its listing filtered by `origin_region`, bounded by its own watermark for
  that origin, so it never lists an entry it has not consumed contiguously.
  The origin's egress becomes its number of eager children times `S` rather
  than `(R-1) x S`; total WAN bytes are unchanged.
- **The tree tunes itself.** A child that keeps seeing a record on the
  origin's listing before its parent holds it promotes the origin (or another
  gateway) to eager and demotes the parent; a parent that only delivers what
  the child already has is demoted. A parent that answers `Absent` for a
  record it declined falls back to the origin for that body, so capacity
  decisions stay local (INV-9).
- **Optionally, lazy links go through the parent too**, bounded the same way,
  which cuts a gateway's connections from `R-1` to the tree degree at the
  cost of one hop of latency on descriptors. That is the lever if the clique
  itself ever hurts.

Cost when it is needed: one query parameter on the existing listing, a
per-link mode on the puller, and the promote/demote rule. Same port, same CA,
same capability-negotiated migration. It delivers one copy per node, which is
what the bandwidth argument wants; a gossip mesh delivers about its degree in
copies by design.
