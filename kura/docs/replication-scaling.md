# Replication At Scale: Problem, Design Space, And Candidate Designs

Status: research / design options. Nothing here is decided or implemented.

This document analyses why Kura's current replication mechanism does not scale
with mesh size or write burst size, surveys the distributed-systems techniques
that could replace it, and proposes two candidate designs plus two composable
mechanisms and a set of cheap non-structural fixes. It is deliberately
opinionated about trade-offs and explicit about what each design gets wrong.

---

## 1. Summary

Kura replicates by **direct mail with per-target durable queues**: every local
write enqueues one outbox row *per peer* in the same atomic batch as the commit,
and a background worker pushes each row to its peer. That design has three
properties that do not survive growth:

1. **Work is proportional to `writes x peers` and lands entirely on the node
   that is already the hot one.** The write-receiving node pays `N-1` times the
   bytes, `N-1` times the request overhead, and `N-1` extra RocksDB puts inside
   the synchronous commit batch.
2. **Replication backpressure is coupled to client write availability.** The
   outbox has a depth cap (`DEFAULT_OUTBOX_MAX_DEPTH`, 100k) shared across
   targets; when the slowest peer's backlog fills it, the node starts shedding
   *client writes* with `429`. A burst of 100k objects against a 5-node mesh
   reserves 400k slots against a 100k cap.
3. **There is no steady-state anti-entropy.** Convergence is only as good as the
   queue: a dropped message, a departed-and-returned peer, or an absence longer
   than the backfill window leaves permanent divergence, because the backfill
   walker is edge-triggered on membership rather than continuous.

The recommendation, in order of value per unit of risk:

- **Take the cheap fixes first** (§6). Outbox rows deduplicated by artifact with
  a per-target bitmap, per-target depth accounting, and a receiver-side
  `have`/`want` exchange are days-to-weeks of work and remove the acute failure
  without a redesign.
- **The design itself now lives in
  [`replication-design.md`](replication-design.md)**, which is the only
  normative document. Everything here is either the background that produced it
  or an option deliberately left out of it.
- **Invert the direction: replace per-target push queues with a per-node
  live index of what each node holds, ordered by arrival, that peers scan
  forward at their own pace** (§7). This
  removes the write-path amplification, removes the shed-writes failure mode,
  removes head-of-line blocking between peers, gives free per-peer pacing, and
  collapses "steady-state replication" and "cold catch-up" into one mechanism.
- **Then make the topology cost-aware**: bytes cross a region boundary
  once, not once per remote node, through one controller-designated gateway per
  region — normally an idle replica, necessarily the serving one where a region
  has a single instance.
- **Then make eagerness a policy rather than a constant**: metadata everywhere,
  bytes by class and demand (§8). This is the biggest possible bandwidth
  win and also the riskiest, because its value depends entirely on a number
  nobody has measured yet: cross-region read overlap.
- **Under all of it, a low-rate reconciliation floor** so convergence does not
  depend on a queue never losing a message (Mechanism C).

---

## 2. What Kura does today

Mechanism, precisely (see `src/replication/mod.rs`, `src/store.rs`,
`src/backfill/`):

- **Enqueue.** `Store::append_artifact_replication_messages` writes one
  `OutboxMessage` per replication target into `ROCKSDB_CF_OUTBOX` inside the
  same `WriteBatch` as the manifest commit, which is written with
  `ApplyDurability::Sync`. Slots are reserved atomically before the batch
  against `outbox_max_depth`; exhaustion returns an error that the HTTP layer
  maps to `429` + `Retry-After` (`capacity_shed_response`).
- **Key layout.** `{lane}-{now_ms:020}-{uuidv7}` where lane `0` is metadata
  (inline artifacts, namespace deletes) and lane `1` is bulk (segment-backed
  bodies). The lane prefix gives metadata strict priority, and the target is
  *not* in the key, so messages for different peers interleave. Note the lane
  test is storage kind, not size: a 4 MiB inline entry rides the priority lane
  alongside 200-byte ones.
- **Drain.** `process_outbox` first runs `drain_metadata_batches`, which
  re-scans from the outbox head each round, buckets inline upserts by target
  across a bounded scan window, and ships up to `REPLICATION_BATCH_MAX_ITEMS`
  (512) / `REPLICATION_BATCH_MAX_BYTES` (8 MiB) per request to
  `PUT /_internal/replicate/artifacts`, with the per-target batches concurrent
  up to `OUTBOX_MAX_INFLIGHT`. Everything else goes through a pipelined
  per-message pass with 32 concurrent deliveries, each streaming one body.
  Every delivered message costs a RocksDB delete.
- **Apply.** Receivers apply with `replication_targets: &[]` — they never
  forward. Conflicts resolve last-writer-wins on `version_ms`.
- **Deletes.** `ReplicationOperation` has exactly two variants, so the only
  removal that propagates is `DeleteNamespace`. It is backed by a live row in
  `ROCKSDB_CF_NAMESPACE_TOMBSTONES` (key `namespace_id`, value `version_ms`,
  overwritten in place on re-delete, never reaped) whose job is
  anti-resurrection rather than deletion: `namespace_tombstone_blocks` gates
  both artifact persist paths and `artifact_apply_outcome`, so an upsert older
  than the tombstone loses whichever order the two arrive in. Eviction and the
  action-cache cascade propagate **nothing** — there are no per-artifact
  tombstones — and the `delete_everything` branch (`version_ms == 0`) writes no
  tombstone and enqueues nothing at all.
- **Catch-up.** `src/backfill/` walks a peer's per-entry index
  (`backfill/idx/` in `ROCKSDB_CF_KEY_VALUE`, keyed by inverted `version_ms` +
  kind + record id) newest-first inside a window bounded by
  `max(ring horizon, per-peer watermark)`, pulls missing bodies in 32 MiB
  batches from `POST /_internal/backfill/bodies`, and advances a durable
  watermark on pass completion. It is scheduled by the membership loop on
  join / re-join / a one-shot "seam" follow-up — not continuously.

Note what already exists and is worth keeping: a version-ordered per-entry
index, a batched pull-based body endpoint with framed streaming and group-commit
durability, a claim set that prevents duplicate concurrent work, an adaptive
shared bandwidth limiter, resumable ranged artifact GETs, and content-addressed
keys for CAS blobs.

### 2.1 Naming: sync forward and sync backward

"Replication" and "backfill" named two mechanisms that worked differently — one
pushed, one pulled — so the names had to carry that difference. Under the
designs below both are pulls over the same wire, differing only in *which
direction through a peer's history they travel* and *how that history is
ordered*. The names should say that:

| Old name | New name | Travels |
| --- | --- | --- |
| Replication (outbox push) | **sync forward** | Follows a peer's log *forward* from where this node left off, ordered by the peer's append sequence — the order things were added. |
| Backfill (catch-up walker) | **sync backward** | Walks a peer's history *backward from newest*, ordered by `version_ms` — how recent the content is. |

One ambiguity to close in the code and the docs, because readers will guess
wrong otherwise: forward and backward describe **travel through the peer's
history**, not the direction data flows. Both syncs pull, and both bring data
*in*. A one-line definition next to each type is enough to keep that straight.

Rename the concepts, the modules and the metrics; **do not rename the wire or
the keyspace in the same change**. `/_internal/backfill/*`, the
`backfill/idx/` key prefix and `ROCKSDB_CF_OUTBOX` are all things an
adjacent-version peer or a rolled-back binary depends on. Renaming code and
documentation is free; renaming a route is a version-skew problem and renaming
a key prefix is a data migration. Introduce the forward-sync route and key
prefix under the new naming, leave the existing ones alone, and alias later if
it is ever worth the churn.

---

## 3. Why it does not scale

**L1 — Fan-out amplification at the worst possible node.** Egress from the
write-receiving node is `(N-1) x S`. With two co-located replicas per region the
loopback copies are cheap in bytes but still cost that node's CPU, connections,
and FDs, and they share the same 32-slot pipeline as the WAN copies. The node
under bursty client load is the node doing all the replication work.

**L2 — Write availability is coupled to the slowest peer.** One depth cap,
shared by all targets, reserved `N-1` at a time. An unreachable peer's backlog
consumes the budget that the healthy peers' messages need, and then client
writes get `429`. This is the failure the "hits the replication limit" symptom
describes. Cassandra learned the same lesson with hinted handoff: hints must be
bounded, and once bounded they cannot be the convergence mechanism.

**L3 — Commit-path cost.** Every write pays `N-1` extra puts inside a
*synchronous* batch, plus `N-1` later deletes, plus the resulting WAL bytes and
compaction. For a 100k-object burst on a 5-node mesh that is 400k puts and 400k
tombstones on the hot node's critical path, for data that is pure routing state.

**L4 — Blind pushes.** The sender does not know what the receiver has. An
object the peer already obtained (from a third node, or from an earlier build,
or because it is content-addressed and identical) is re-sent in full. There is
no `have`/`want` negotiation, and content addressing — which makes that
negotiation exact and free for CAS blobs — is not exploited. Worse, the sender
also does not know whether the receiver will *keep* the object: bytes are
shipped and only then run through the receiver's ring admission and eviction.

**L5 — No continuous anti-entropy.** Messages are dropped for targets that left
the mesh view; a rejoining peer only re-walks back to the backfill horizon; the
walker is edge-triggered. Convergence therefore depends on a queue never losing
anything and on membership events firing at the right times. There is no
mechanism whose job is "find and fix divergence", only mechanisms whose job is
"deliver this message" and "catch up a new node".

**L6 — Priority is two-valued and global.** Two lanes, one shared inflight
budget, one shared bandwidth limiter. There is no per-peer isolation: a
far-away peer's 2 GB backlog occupies inflight slots that the local sibling —
whose convergence is the thing rollouts depend on — needs.

---

## 4. What convergence has to mean here

### 4.1 Three classes of state, three different requirements

| Class | Shape | Size | Requirement |
| --- | --- | --- | --- |
| Inline entries (`KeyValue` kind: REAPI action-cache entries and generic key-value writes) | mutable key -> value, LWW on `version_ms` | usually ~100 B – few KiB, but bounded only by `MAX_INLINE_REPLICATION_BODY_BYTES` (4 MiB); the generic key-value route defaults to 1 MiB (`KURA_MAX_KEYVALUE_BYTES`) and is config-capped at the same ceiling. Very high count | Must be **complete and fast** everywhere. This is what makes a node "warm". |
| CAS blobs / segment artifacts | immutable, content-addressed (`blob/{hash}/{size}`) | KiB – 2 GB, all the bytes | Must be **available**, not necessarily local. |
| Namespace tombstones | rare, ordering-sensitive | tiny | Must not be lost or reordered against their upserts. |

The asymmetry is the whole opportunity: class 1 is *usually* small enough to
replicate everywhere unconditionally and cheap enough to do eagerly; class 2 is
where every byte of cost lives and is the only class where "do we actually need
this here?" is a question worth asking.

The word *usually* is load-bearing, and three consequences follow from it:

- **The class split has to be by size, not only by kind.** A namespace whose
  clients write megabyte-scale key-value entries turns the "metadata plane"
  into a bulk plane. Every rule below that says "inline" should be read as
  "under the piggyback threshold"; entries above it belong in the bulk lane
  regardless of kind, and today's lane split — which keys on
  `is_bulk()` == "segment-backed" — does not make that distinction.
- **Inline does not mean piggyback-eligible.** A 4 MiB entry cannot ride a page
  frame; the threshold is a byte budget, not a storage-kind test.
- **Inline replication buffers the whole body in RAM on both sides**, so the
  priority lane's transient memory is `entry size x in-flight`, which at the
  ceiling is megabytes per delivery rather than kilobytes. That is the same
  admission budget everything else in the node is careful about, and it is one
  more reason for the receiver — not the sender — to decide the rate.

An important coupling constrains any answer: an action-cache entry and the CAS
blobs it references form one integrity unit. Kura already maintains the reverse
index and cascade-deletes entries stranded past a grace window
(`src/action_cache_refs.rs`, the snapshot serve path). Any design that
replicates entries without their blob closure must either extend that rule to
understand remote-backed blobs, or refuse to *serve* an entry it cannot fully
back — see §8.

Producer matters too. For REAPI the value of a replicated blob is mostly that
it backs an `ActionResult`; for Xcode, Gradle, Module, Nx and Metro the artifact
body *is* the hit, so any policy that withholds bodies degrades those producers
directly.

### 4.2 It is a cache, not a database

Two consequences that most of the classical literature does not assume:

- **Divergence is partly intentional.** Every node evicts independently under
  its own capacity and memory pressure. Anti-entropy that treats every set
  difference as damage will fight eviction forever and thrash the segment ring.
  Any reconciliation mechanism must be scoped to a recency window and must
  respect the local admission decision.
- **A miss is legal.** Losing a replica's copy costs latency, never
  correctness. That buys enormous freedom: no quorum, no synchronous
  replication, no per-key causal metadata, and a legitimate option to not
  replicate bytes at all.

### 4.3 Cost model

With `N` nodes across `R` regions, `r_i` co-located replicas in region `i`,
and `S` bytes written into region 1 during a burst:

| | Origin egress | WAN bytes |
| --- | --- | --- |
| Today | `(N-1) x S` | `(N - r_1) x S` |
| Forward index only (§7) | `(N-1) x S` | `(N - r_1) x S` |
| + region relay (Mechanism D) | `(r_1 - 1) x S` loopback + `(R-1) x S` WAN | `(R-1) x S` |
| + class/demand policy (§8) | as above, with `S` replaced by the replicated subset | `(R-1) x S_eager + S_demand` |

The forward index alone does not move a single byte less. It is about *control*: who
decides, at what rate, with what failure isolation, and at what cost to the
write path. The gateway topology moves the bytes. §8 decides which bytes exist at
all. They are independent and can ship in that order.

---

## 5. Design space survey

### 5.1 Direct mail with per-destination hint queues (today)

*Where it comes from:* Demers et al.'s "direct mail"; Cassandra hinted handoff;
Dynamo hinted handoff.

*Fit:* Simple and low-latency when everything is healthy. Every production
system that started here added an anti-entropy layer underneath, because a
bounded hint buffer cannot be a convergence guarantee (Cassandra discards hints
past `max_hint_window` and documents repair as the actual mechanism). Kura is at
exactly that point.

### 5.2 Gossip / epidemic dissemination (push, pull, push-pull)

*Where it comes from:* Demers et al., "Epidemic Algorithms for Replicated
Database Maintenance" (1987).

*Fit:* The **push-pull anti-entropy** idea is exactly right; the **randomised
peer selection** is not. Randomisation buys robustness at `N` in the hundreds
where you cannot maintain full membership or a topology map. Kura has `N <= ~8`,
authoritative membership from the control plane, and highly asymmetric link
costs (loopback vs. WAN). Deterministic "everyone tails everyone, preferring
cheap sources" strictly dominates randomised gossip here. Rumor-mongering's
"stop spreading after `k` redundant deliveries" heuristic is likewise pointless
at this size.

### 5.3 Merkle trees over key ranges

*Where it comes from:* Dynamo, Cassandra, Riak AAE.

*Fit:* Poor as a primary mechanism, acceptable as a repair mechanism. Tree
maintenance is a hot-path cost, rebuilds are the classic operational complaint
(Riak's TicTac AAE exists specifically to make the trees cheaper by dropping
cryptographic strength), a single differing leaf drags a whole range, and a
cache's continuous eviction churns the leaves permanently.

### 5.4 Range-based set reconciliation (RBSR)

*Where it comes from:* Meyer, "Range-Based Set Reconciliation" (2023); the
Willow protocol's `ReconciliationSendFingerprint`.

*Fit:* Strictly better than a static Merkle tree for this use: no tree to
maintain, recursion adapts to where the differences actually are, `O(log n)`
round trips, and the fingerprint only needs to be a monoid over an ordered
range (an XOR or sum of per-entry hashes), which is incrementally maintainable
over an already-ordered index. Good candidate for the repair floor.

### 5.5 IBLT / rateless IBLT / minisketch

*Where it comes from:* Eppstein et al.'s difference digests; Bitcoin's Erlay
and minisketch; Yang, Gilad, Alizadeh, "Practical Rateless Set Reconciliation"
(SIGCOMM 2024).

*Fit:* Near-optimal bytes when the difference is small and you do not want
round-trip recursion — the ideal "prove these two siblings are identical"
primitive, where the expected difference is zero and the exchange is a few
hundred bytes. Rateless IBLT removes the need to guess the difference size up
front, which was the historical reason not to use IBLTs. Weaknesses here: it
reconciles a *set of fixed-size symbols*, so you sketch `hash(key) XOR version`
and then need a local hash -> key lookup; and it tells you nothing about *why*
an element is missing, which matters when the answer is "I evicted it on
purpose".

### 5.6 Version vectors, dotted version vectors, node-wide clocks

*Where it comes from:* Riak's DVVs; Gonçalves et al., "Concise Server-Wide
Causality Management" and DottedDB ("anti-entropy without Merkle trees").

*Fit:* The **node-wide clock** idea is the single most transferable one: a
per-node monotonic sequence plus a per-peer "what I have seen from you" cursor
gives anti-entropy with `O(peers)` state and no Merkle trees. That is precisely
§7. The **per-key causal metadata** is not needed: Kura's conflict rule
(LWW on `version_ms`) is adequate for a cache, where a wrong winner costs a
later miss rather than data loss.

### 5.7 Delta-state CRDTs

*Where it comes from:* Almeida, Shoker, Baquero, "Efficient State-based CRDTs
by Delta-Mutation".

*Fit:* Good as a framing rather than as machinery. Kura's data model is already
CRDT-shaped: the action-cache namespace is an LWW map, the CAS namespace is a
grow-only set modulo eviction. Delta-CRDT anti-entropy = ship delta-intervals,
ack them, and fall back to full-state join when the buffer is GC'd. Map that
onto §7 with one adjustment: the forward index plays the delta-interval role,
the cursor is the ack, and the recency-windowed walk is the full-state entry
point. The adjustment matters — a live index is a *state* view rather than a
buffered interval, so what a follower receives is the current value, not the
sequence of values that produced it. The useful invariant it
names is that deltas must ship as *intervals* — an unbroken prefix — which is
exactly what makes a single scalar cursor sound.

### 5.8 Quorum / Dynamo-style RF < N

*Fit:* Reject. Every region must serve its own clients locally, so the
replication factor is dictated by "who needs a local copy", not by durability.
Quorum adds write latency to a system whose entire value proposition is local
latency. Sharding *within* a region across the two replicas would halve storage
but destroy the rollout-warmth property that the second replica exists for.

### 5.9 Log-based replication with pull cursors

*Where it comes from:* Kafka follower fetch; Postgres logical replication slots;
DynamoDB Streams / global tables.

*Fit:* The best structural match. Pull puts flow control with the party that
knows its own capacity, makes per-peer isolation automatic, reduces sender state
to `O(1)` (one ordered log everyone reads) instead of `O(peers x backlog)`, and
makes "recover after downtime" the same code path as "keep up", differing only
in cursor distance. Kafka's *compacted topic* names the property §7 needs for a
rewritten key — retain only the newest record — though §7 gets it structurally,
by re-keying a live row, rather than by running a compactor over a log.

### 5.10 Content addressing and dedup

*Fit:* Under-exploited today. `blob/{hash}/{size}` means "does the peer have
this exact object" is answerable exactly, cheaply, and without conflict
resolution. A puller trivially knows what it is missing; a pusher does not.
This alone is a strong argument for inverting direction. Content-defined
chunking (BuildBuddy reports ~85% dedup within eligible large writes with
FastCDC at ~512 KiB chunks) is a much bigger change: it alters the storage
format, which collides with Kura's rollback-safety rule. Treat chunking as a
*transport* concern first (resumable ranged fetches) and a storage concern much
later, if at all.

### 5.11 Peer-to-peer distribution trees and swarms

*Where it comes from:* BitTorrent; Uber Kraken; Dragonfly; Meta's Owl (OSDI
'22).

*Fit:* Two separable ideas. (a) **Bytes should traverse an expensive link once**
and then spread over cheap links — that is the region-relay idea, and it is the
single largest byte-level saving available without changing *what* gets
replicated. (b) **Chunked, multi-source, resumable transfer** — valuable for the
2 GB tail, where a fixed peer timeout against a slow sender currently means
restarting from zero. Owl's lesson is also worth taking: centralising the
*decision* (which peer fetches from which) is not a scalability problem at this
size, and Kura already has a control plane that distributes membership. The
Kraken-vs-Dragonfly comparison is the relevant caution: a coordinator that
touches every chunk becomes the bottleneck; a coordinator that only shapes the
graph does not.

### 5.12 Demand-driven cache hierarchies

*Where it comes from:* Squid's ICP and Cache Digests; CDN parent/sibling
hierarchies; Netflix EVCache cross-region replication (metadata over Kafka, a
regional relay fetches the value locally and pushes it); Buildbarn's
`MirroredBlobAccess` + `ReadFallbackBlobAccess`.

*Fit:* Directly applicable, and Kura is better positioned than Squid: Squid had
to *approximate* peer contents with a Bloom filter and live with false hits,
whereas Kura's replicated metadata plane is exact. If metadata is everywhere,
"which peer has this object" is a local lookup with no probing and no false
positives. That is the deferred option in §8.

### 5.13 Peer-to-peer overlay and swarm protocols

§5.11 covered the production P2P *systems*; this covers the algorithm-level
work, because that is where the closest analogues to both candidate designs
turn out to live.

The framing first, because it decides most of the verdicts: **what transfers
from P2P is the data plane, not the control plane.** Most P2P algorithms spend
their complexity on problems Kura does not have — membership that is unknown
and churning at internet scale, peers that are untrusted or selfish, NAT
traversal, no authoritative directory — and pay for those solutions with
machinery Kura would only be burdened by: routing overlays, partial views,
random peer sampling, incentive mechanisms. Kura has at most a handful of
nodes, all operated by us, with authoritative membership from a control plane
and link costs that are known in advance and wildly asymmetric. What does
transfer is how those systems move bytes: eager-versus-lazy push with digest
announcements, want-lists over content addresses, state replicated
by difference, and verified chunk-level multi-source transfer.

**Plumtree / epidemic broadcast trees** (Leitão, Pereira, Rodrigues, SRDS 2007;
usually paired with HyParView). *Adopt the mechanism, drop the overlay.* Every
node forwards the payload eagerly on a subset of its links — the spanning tree
— and sends only cheap `IHAVE` digests on the rest. A node that keeps learning
about a payload from an `IHAVE` before the payload itself promotes that link to
eager and demotes the one that was slow, so the tree repairs itself around
failures and slow links with no coordinator and no static designation.

This is a better-specified version of two things this document proposes by
hand. It is Mechanism D.1's relay, except the topology is self-tuning rather
than a nominated gateway with a staleness fallback bolted on. And the
eager/lazy split *is* §8's two planes: eager-push the metadata and small
inline entries, lazy-announce the large bodies, pull them on demand. That two
independent lines of reasoning landed on the same shape is the strongest
argument in this document for that shape being right. Kura does not need
HyParView — membership is authoritative, not sampled — so what is adopted is
the tree construction and repair rule, not the overlay underneath it.

**Bitswap** (IPFS). *Adopt the want-list shape, and heed its history.* Bitswap
splits wants into `WANT_HAVE` (do you hold this CID?) and `WANT_BLOCK` (send
it), which is exactly the `have`/`want` exchange proposed as Design 0 item 3.
Its production history is the cautionary half: naive broadcast want-lists made
peers receive the same block from every partner — around twenty copies of each
file in early testing — and the fix was sessions with per-peer HAVE probes and
an *adaptive split factor* that widens the peer set on timeouts and narrows it
when duplicates rise. That adaptive rule is directly reusable as D.2's
multi-source fetch policy, and it is the cheapest known answer to §7's
residual duplicate-transfer weakness.

**Hypercore / Dat.** *Validates §7's shape and improves it in two places.* A
Hypercore is a per-writer append-only log; peers replicate it by comparing
lengths and sending the difference, advertise what they hold as a **compressed
bitfield** of log ranges, and support **sparse replication** — pulling
individual blocks with a Merkle proof against a signed root. §7 is the same
shape, with one deliberate divergence: Hypercore's log is append-only and grows
with writes, while §7's forward structure is a live index that grows with live
data. Two details worth stealing: the bitfield is a more compact
have-summary than a per-record presence index for anything range-shaped
(segment-aligned bodies especially), and proof-carrying partial replication is
what lets a peer accept a block from an untrusted source. The signing is
unnecessary here — one operator, one trust domain — and content addressing
already gives CAS blobs the same end-to-end check for free; inline entries are
the class that has no such check today.

**DHTs and structured overlays** (Chord, Kademlia, Pastry, Tapestry).
*Reject.* Key-based routing exists to answer "which node is responsible for key
`k`" among thousands of churning nodes without a directory. Kura wants the
metadata plane replicated in full to every node, which makes that question a
local lookup; adding `O(log N)` routing hops would add latency and failure
modes to a question that is already answered. Kademlia earns its place in IPFS
for provider discovery at internet scale; Kura's provider discovery is the log.

**SplitStream and multi-tree striping.** *Partially applicable, not yet worth
it.* Its insight is real and does apply: stripe the content over
interior-node-disjoint trees so every node contributes upload bandwidth rather
than leaving capacity idle — and Kura does have idle capacity, in the standby
replica of every region. But striping pays off when there are many nodes per
region to spread stripes across, and it multiplies the coordination. At five
nodes, "prefer the cheapest source that has it" captures most of the same
benefit for a fraction of the machinery.

**Fountain and network codes** (Raptor/RaptorQ, RFC 6330; Avalanche).
*Interesting, deferred, and probably wrong here.* Encoding a body into rateless
symbols dissolves the coordination problem completely: any *k′* symbols
reconstruct the object, so two peers pulling concurrently never fetch the same
symbol and no claim set or lock is needed. That is a clean answer to §7's
duplicate-transfer weakness. The cost is disqualifying for this system: coded
symbols are not the stored bytes, so every response would need an encoder in
the path, which forfeits the `sendfile`/`splice` accelerator and the mmap
serving path that exist precisely because the body on disk is the body on the
wire. Revisit only if fan-out grows enough that coordination, rather than
bandwidth, is the bottleneck.

**PPSPP** (RFC 7574). Not a design so much as a wire-format reference: the
standardised form of "swarm plus a Merkle hash tree over chunks", worth reading
before designing D.2's chunk framing if per-chunk verification is ever needed.

**Tit-for-tat, choking, rarest-first.** *Reject, trivially.* Incentive
mechanisms solve selfishness among strangers; every node here is ours.
Rarest-first exists to stop piece starvation in a swarm whose seeds depart;
Kura's source is durable, known, and not going anywhere on the timescale of a
transfer.

---

## 6. Design 0 — cheap fixes that need no redesign

Worth stating explicitly, because a redesign is months of careful work and the
acute symptom can be removed in weeks. These are not mutually exclusive with
anything below.

1. **Deduplicate outbox rows by artifact.** Key the row by `artifact_id`
   (plus lane) and store a per-target pending bitmap in the value instead of
   one row per target. Write-path puts drop from `N-1` to 1, the depth cap
   becomes a count of *objects* rather than *deliveries*, and a rewritten key
   collapses to one row. This alone changes the 100k-object / 5-node burst from
   400k slots to 100k.
2. **Per-target depth accounting and shedding.** A single unreachable peer
   should not be able to consume the whole budget. Track depth per target;
   when one target exceeds its share, stop enqueuing *for that target* and
   record the gap for the backfill walker instead of failing the client write.
   The write path should never fail because one peer is down.
3. **Receiver-side `have`/`want` before bulk bodies.** One extra round trip per
   batch: send the ids and sizes, the receiver answers with what it wants
   (applying its own admission rule), then stream only those. For
   content-addressed blobs the answer is exact. This is the cheapest fix for L4
   and it composes with everything.
4. **A relay hop for cross-region delivery.** Even in the push model, sending
   to one node per remote region and letting it forward intra-region halves WAN
   bytes wherever a region has two replicas. Requires the receiver to be allowed
   to enqueue forwarding messages for same-region peers only, with a hop count
   to prevent loops.
5. **Run the backfill walker on a slow timer, not only on membership edges.**
   A pass per peer every `N` minutes turns "permanent divergence until a
   membership event" into "bounded divergence", using code that already exists.

Items 1, 2 and 5 are small and remove the acute failure. Item 3 is the highest
bandwidth-saving-per-line change available. Item 4 is the only one that needs
real protocol thought in the push model, and it is subsumed by Mechanism D if
§7 happens.

---

## 7. The design

**The design now lives in its own document:
[`replication-design.md`](replication-design.md).** It is the normative one;
this document is the analysis that produced it.

In one sentence: every node maintains a live index of what it currently holds,
ordered by the sequence in which it arrived; peers scan it forward at their own
pace with a durable cursor; a controller-designated gateway per region is the
only node that crosses a region boundary; and the outbox and its per-target
queues disappear.

The design document covers the forward index and its cursor, why the two sync
directions need two differently-ordered indexes, what a live index cannot
express and why that is fine here, the gateway topology and its selection rule,
the invariants the whole thing rests on, and the measured memory and CPU cost.
Sections below that reference "§7" mean that document.


## 8. Deferred option — two-plane replication: metadata everywhere, bytes by policy

*Not part of §7. Recorded here because it is the largest remaining bandwidth
lever and because the measurement that would justify it is worth taking; it
must not ship as a default before then.*

**One sentence:** the log (what exists, where) replicates to everyone eagerly
because it is small; bodies replicate according to class, destination cost, and
demand.

### v1 — the naive form

Plane 1 (metadata) is §7's forward index, always fully scanned by everyone. Plane 2
(bodies) is fetched when policy says so:

- action-cache entries and inline artifacts under the threshold: always,
  everywhere (large inline entries follow the body policy, like any other bulk
  object);
- intra-region sibling: everything (loopback is free and rollout warmth needs
  it);
- cross-region: only on demand — a local miss for a key the metadata plane says
  a peer holds triggers a peer fetch, served through to the client and cached
  locally.

This is EVCache's cross-region pattern (ship the key, let the far side fetch the
value) combined with Squid's sibling-hierarchy miss path — except the "who has
it" answer is exact rather than a Bloom filter, so there are no false hits.

### v1's three serious problems

1. **Stranded action-cache entries.** A peer holding an entry whose blobs are
   not local trips the existing strand cascade and deletes the entry after the
   grace window — and, worse, could serve a hit whose outputs it cannot deliver.
2. **Read-path latency and a new failure mode.** A cross-region body fetch on
   the read path adds an RTT plus transfer time, and makes a local read depend
   on a remote node being up.
3. **Cold standby after a regional failure.** Metadata without bytes means a
   surviving region has an index of things it cannot serve, and a stampede of
   on-demand fetches toward a region that may be exactly the one that died.

### v2 — fix them

4. **Reference-closure eagerness instead of pure demand.** Replicate a blob
   eagerly iff some action-cache entry references it. Kura already computes
   `referenced_blob_keys` and maintains the reverse index, so the closure is
   known. This preserves the integrity unit *and* naturally excludes the
   input/intermediate blobs that no `ActionResult` ever references — which for a
   REAPI cache is a large share of uploaded bytes that produce hits on no other
   node. Caveat: tree-output leaves are deliberately not walked today, so the
   closure is incomplete for `output_directories` shapes.
5. **Separate "advertise" from "serve".** A node tails the whole log (so it
   knows what exists and where) but only *serves* what it can fully back
   locally. Apply order is blobs, then the entry that references them — which
   per-node log ordering gives for free. This keeps the strand rule purely
   local, which matters: making a local GC rule depend on distributed state is
   how you get correlated cache deletions during a partition.
6. **Best-effort demand path.** Single-flight per key, short negative caching, a
   hard deadline after which the fetch degrades to a plain miss. Never an error,
   never a stall longer than a local miss would have cost.

### v3 — coarse subscriptions instead of per-object demand

7. **Subscribe by namespace x recency rather than per object.** "Namespace X is
   hot in region B" pulls the whole recent working set for X ahead of demand,
   which captures most of the bandwidth saving with none of the per-read
   latency. Far easier to reason about, to bound, and to explain to a customer
   than per-object demand.
8. **Make it a per-tenant / per-peer-pair policy** with a conservative default:
   `full` (today's behaviour), `referenced` (closure only), `subscribed`
   (namespace-scoped), `metadata_only`. It plugs straight into the existing
   per-tenant egress shaping: "spend at most X MB/s on speculative cross-region
   replication; everything else is demand-driven".

### Pros

- The only design here that reduces total bytes by a large factor rather than a
  small one.
- Metadata-complete nodes make peer selection exact and probe-free.
- Eagerness becomes a cost dial per tenant rather than a constant.

### Cons and limits

- **Its value rests entirely on an unmeasured number: cross-region read
  overlap.** If two regions build the same monorepo from the same commits — the
  common case for one company with two offices — overlap is high, demand-driven
  replication saves nothing, and it *adds* latency to reads that would have been
  local hits. If the regions serve different products or teams, overlap is low
  and the saving is large. Measure per tenant before defaulting it on; keep it a
  policy, never a constant.
- Non-REAPI producers degrade: for Xcode/Gradle/Module/Nx/Metro the body is the
  hit, so `metadata_only` turns every hit into a serve-through.
- Introducing a second notion of "have" (advertised vs. servable) touches every
  presence gate in the system: the snapshot serve path, the strand cascade, ring
  capacity accounting, readiness. Wide blast radius in code that is already
  subtle.
- A region that has never pulled a body cannot survive the loss of the region
  that has them. Acceptable for a cache; must be an explicit product decision,
  not something discovered during an incident.

---

## 9. Mechanisms that attach to §7 later

### Mechanism C — a reconciliation floor

Purpose: guarantee convergence without trusting cursors or retention.

Shape: low-rate, continuous, **metadata-plane only**, scoped to a recency
window, respecting local admission decisions. Peers exchange a compact summary
of their entries newer than `T` and pull whatever the difference says they are
missing; the *action* is a normal §7 fetch.

Two viable primitives:

- **Rateless IBLT** for the common case, where the expected difference is zero
  or tiny: a few hundred bytes per peer-pair per minute, no recursion,
  self-terminating. Sketch `hash(artifact_id) XOR hash(version_ms)` so a stale
  copy shows as a difference on both sides.
- **Range-based set reconciliation** when the difference is large (after a long
  absence), because it degrades gracefully and needs no size estimate.

Why it must not be the primary mechanism: replicas diverge on purpose. Without a
recency window and a "this was declined, not lost" signal, reconciliation
re-fetches what a node just evicted and thrashes the ring. Scoped correctly it
is cheap insurance — and insurance that is never exercised is insurance that is
broken when needed, so it needs deliberate fault injection (the `failpoints`
module is the right home).

### Mechanism D — region-aware relay and chunked transfer

**D.1 Relay, built as a Plumtree.** Bytes cross a region boundary once. Under
§7 the first cut is pure source-selection policy: each puller prefers the
cheapest source that has *materialised* the object (same node / loopback > same
region > same continent > origin). Trees emerge; no coordinator is required.
Because "materialised" is monotone, there is no deadlock — only delay.
Nominating the idle standby replica as the region gateway also moves the WAN
work off the replica serving client traffic.

The weakness of that first cut is that the topology is static: a nominated
gateway that falls behind slows its whole region, and the mitigation — "prefer, do not
require", plus a staleness threshold — is hand-rolled. Plumtree's repair
rule replaces it with something self-tuning: a node that repeatedly learns
about a record from a peer's cheap announcement *before* the record itself
arrives on its eager link promotes the announcing link and demotes the slow
one. The tree then re-forms around a failed or lagging gateway automatically,
which is the same property the static version needs an operator to supply.

- Cost: one extra hop of latency for the far region. Under the self-tuning
  form, also a settling period after a topology change, and a tuning risk —
  promotion thresholds that are too eager oscillate between links.

**D.1b The explicit gateway topology** is a decided part of the design and has
moved to the design document. What remains here is the rationale it rests on: D.1's
source-preference rule and Plumtree's repair signal.

**D.2 Chunked, resumable, multi-source body transfer.** Fetch large bodies as
ranged chunks with per-chunk retry and possibly multiple sources. Kura already
serves `Range` and advertises `Accept-Ranges`, so this is transport-only — no
storage format change, which matters given the rollback-safety rule. It fixes
the failure class where a fixed peer timeout against a slow sender restarts a
multi-GB transfer from zero. Content-defined chunking for cross-artifact dedup
is a separate, much larger track and should stay out of scope initially.

- Cost: more in-flight requests and FDs against a strict FD budget; parallelism
  must be budgeted explicitly alongside the existing memory reservations.

---

## 10. Failure and recovery behaviour

| Scenario | Today | §7 (+C/D) |
| --- | --- | --- |
| Peer down minutes | Backlog accumulates against a shared cap; healthy peers' deliveries compete for the same budget; risk of shedding client writes | The peer's cursor stops advancing. Nothing else changes anywhere. |
| Peer down for days | Messages may be pruned when it leaves the mesh view; re-join walks back only to the horizon | Nothing expires. The cursor resumes where it stopped and the peer scans forward until it converges — no retention window, no falloff, no fallback path |
| Network partition, both sides writing | Both queue; on heal both drain; LWW resolves | Both resume scanning on heal; LWW resolves; C catches anything below either cursor |
| Origin crashes before replication | Undelivered outbox rows survive locally but nothing propagates until it returns | Same: the index survives; peers resume when it returns |
| Origin permanently lost (PVC gone) | Data written only there is lost | Same. Neither design is durability; if durability is wanted, it needs a separate eager-replication policy for a chosen class |
| Node rebuilt with same identity, fresh disk | Backfill walker re-populates it | **Hazard**: cursors must include an incarnation/epoch or peers silently skip. Design requirement, not an emergent property |
| Rolling restart of a replica | Backfill on re-join, gated by ring fullness | Sibling resumes its cursor, converges in milliseconds over loopback |
| Memory pressure on a receiver | Peer plane returns 503, sender retries, queue grows | Receiver stops pulling. No queue, no retries, no shed writes |
| Slow far peer during a burst | Occupies shared inflight slots and depth budget | Its own cursor lags. Nothing shared |
| Silent divergence (bug, dropped message) | Undetected until someone notices misses | Mechanism C finds it within one reconciliation interval |
| An update lands at a seq below a follower's cursor | n/a | **Permanently skipped, silently.** The monotonic re-keying invariant in the design document is what prevents it; C is the only backstop |
| Peer evicts an object another node believed it held | Sender pushes blindly and finds out on delivery | The row disappears from its index; a stale hint resolves as `Absent` on fetch and falls back to another source |

---

## 11. Recommended composition and migration

Order chosen by value per unit of risk:

1. **Design 0 items 1, 2 and 5** — days to weeks; removes the acute failure.
2. **The forward index and cursors** — the substrate. Removes the write-path
   amplification and head-of-line blocking, and unifies catch-up with steady
   state.
3. **The gateway topology** — controller-designated, riding the existing
   mesh view; halves WAN bytes wherever a region has two replicas.
4. **Mechanism D.2 (chunked resumable fetch)** — fixes the large-artifact
   failure class.
5. **Mechanism C (reconciliation floor)** — replaces "hope no message is lost".
6. **The two-plane class/demand policy (§8)** — last, behind measurement, per tenant.

Migration must be capability-negotiated and reversible at every step, because
mixed-version pods run side by side and rollback must work. A workable sequence:

- **Phase 0.** Add the forward index as a new key prefix in an existing column
  family —
  *not* a new CF: the store opens with an explicit descriptor list
  (`DB::open_cf_descriptors`), so rolling back to a binary that does not know
  the new CF fails to open the database. Dual-write log and outbox; add
  `GET /_internal/log`; advertise support in `/_internal/status`. Old peers
  answer 404 and the puller does nothing — the same fallback pattern already
  used for `PUT /_internal/replicate/artifacts`.
- **Phase 1.** Nodes scan peers that advertise the forward index. Stop enqueuing outbox
  messages for a target once that target confirms it is tailing. Both
  mechanisms coexist; either can be disabled by config.
- **Phase 2.** Once every node advertises tailing, stop enqueuing entirely; keep
  the outbox code for one release.
- **Phase 3.** Reconciliation floor and the policy knobs. Note there is no
  compaction phase: the live index has nothing to compact.

Observability that must ship with Phase 1, or the change is not safe to run:
per-peer cursor lag in both records and seconds; bytes replicated per unique
object (the amplification factor, which is the number this whole effort exists
to move); body fetches deduplicated by source preference; log growth, GC and
reconciliation difference sizes; forward-index row count against live artifact
count, which is the check that re-keying is deleting stale rows rather than
leaking them.
Per `kura/AGENTS.md`, every new metric also needs a panel in
`infra/grafana-dashboards/tuist-kura-details.json`.

---

## 12. Honest critique

**The biggest risk is sequencing, not technique.** This is a rewrite of the most
safety-critical subsystem in a system that must interoperate across a version
skew and roll back cleanly. Every phase has to be independently shippable and
independently revertible, which roughly doubles the work relative to a
clean-slate implementation. That cost is only justified if the shed-write rate
and the amplification factor are actually as bad as the symptom suggests — which
is a measurement, not an assumption. Design 0 exists precisely so that the
measurement can be taken without the fleet on fire.

**The forward index is not a bandwidth fix and should not be sold as one.** It changes who
is in control, not how many bytes cross the WAN. If the actual pain is egress
cost, the gateway topology and §8 are the levers, and both can in principle be retrofitted
onto the existing push model. Pull is still the right substrate — for
availability and isolation reasons, not byte reasons.

**The two-plane option (§8) could be a regression.** If cross-region read overlap is high, it
trades saved bandwidth for added read latency and a new dependency on peer
liveness in the read path. It should never be a default.

**Mechanism C's cost is easy to underestimate.** Incrementally maintained range
fingerprints touch the write path; sketch maintenance under continuous eviction
is fiddly; and it only proves its worth during incidents, so it needs synthetic
exercise to stay honest.

**Pull has a genuine downside the push model does not.** Push delivers at the
moment of the write with no polling and no idle cost. A tail with long-polling
approximates that, but it introduces `N x (N-1)` long-lived streams, interacts
with connection recycling and drain, and turns a stateless sender into one that
must hold and correctly resume per-peer read positions. If mesh sizes ever grow
past a couple of dozen nodes per tenant, this model has to be replaced by an
explicit tree or randomised gossip.

**Things that would change the recommendation:**

- Mesh sizes past ~16 nodes per tenant: the N-to-N tail-stream model stops being
  appropriate; move to a control-plane-computed tree (Owl-style) or randomised
  gossip.
- If most bytes turn out to be a small number of very large artifacts rather
  than many small ones, chunked transfer and content-defined chunking move ahead of §7
  in priority.
- If shed writes turn out to be rare and the real complaint is purely egress
  cost, skip §7 initially and do the gateway topology + §8 on top of the existing
  outbox.

---

## 13. What to measure before committing

1. **Cross-region read overlap**: of the objects written in region A, what
   fraction is ever read in region B, and within what time window? This single
   number decides §8.
2. **Referenced vs. unreferenced CAS bytes**: what share of replicated bytes is
   in the blob closure of some action-cache entry? This bounds the `referenced`
   policy's saving.
3. **Actual shed rate**: how often does `capacity_shed_response` fire for outbox
   exhaustion, and on which nodes? This justifies (or does not justify) Design
   1's priority.
4. **Amplification factor**: replicated bytes divided by unique bytes written,
   per node. The headline metric for D.1.
5. **Object size distribution and rewrite rate per action-cache key**: sizes the
   forward index and the page piggyback threshold. The design document measures this for one
   Rust/Bazel build; the fleet's real distribution is what sets the row count,
   and the row count is what sets the memory cost.
6. **Per-CF `rocksdb.estimate-num-keys` and `estimate-live-data-size`, plus
   block-cache hit/miss**: none of these are exported today, which is why the
   design document's cost section had to be measured by hand against a local
   node. They are cheap RocksDB
   properties and they make the forward-index leak check in §11 possible.
7. **Convergence distribution today**: time from local commit to peer
   visibility, per peer class (sibling vs. cross-region), at burst and at rest.

---

## 14. References

- Demers et al., *Epidemic Algorithms for Replicated Database Maintenance*
  (PODC 1987) — <http://bitsavers.trailing-edge.com/pdf/xerox/parc/techReports/CSL-89-1_Epidemic_Algorithms_for_Replicated_Database_Maintenance.pdf>
- Gonçalves et al., *Concise Server-Wide Causality Management for Eventually
  Consistent Data Stores* — <https://link.springer.com/chapter/10.1007/978-3-319-19129-4_6>
- Gonçalves et al., *DottedDB: Anti-Entropy without Merkle Trees, Deletes
  without Tombstones* — <https://ieeexplore.ieee.org/document/8069082/>
- Almeida, Shoker, Baquero, *Efficient State-based CRDTs by Delta-Mutation* —
  <https://arxiv.org/pdf/1410.2803>
- Meyer, *Range-Based Set Reconciliation* — <https://arxiv.org/pdf/2212.13567>
- Willow Protocol, confidential sync / reconciliation —
  <https://willowprotocol.org/specs/confidential-sync/index.html>
- Yang, Gilad, Alizadeh, *Practical Rateless Set Reconciliation* (SIGCOMM 2024)
  — <https://arxiv.org/abs/2402.02668>
- Flinn et al., *Owl: Scale and Flexibility in Distribution of Hot Content*
  (OSDI 2022) — <https://www.usenix.org/system/files/osdi22-flinn.pdf>
- Leitão, Pereira, Rodrigues, *Epidemic Broadcast Trees* (Plumtree, SRDS 2007)
  — <https://www.dpss.inesc-id.pt/~ler/docencia/rcs1617/papers/srds07.pdf>
- IPFS Bitswap (want-lists, `WANT_HAVE`/`WANT_BLOCK`, sessions) —
  <https://docs.ipfs.tech/concepts/bitswap/>; the duplicate-block history and
  the adaptive split factor —
  <https://blog.ipfs.tech/2020-02-14-improved-bitswap-for-container-distribution/>
- Hypercore / Dat, append-only log replication with have-bitfields and sparse
  replication — <https://www.datprotocol.com/deps/0002-hypercore/>
- Castro et al., *SplitStream: High-Bandwidth Multicast in Cooperative
  Environments* —
  <https://www.cs.princeton.edu/courses/archive/fall09/cos518/papers/splitstream.pdf>
- Uber Kraken — <https://github.com/uber/kraken>
- Squid Cache Digests — <https://wiki.squid-cache.org/SquidFaq/CacheDigests>
- Netflix, *Caching for a Global Netflix* (EVCache cross-region replication) —
  <http://techblog.netflix.com/2016/03/caching-for-global-netflix.html>
- Apache Cassandra, *Hints* (bounded hint window, repair as the real mechanism)
  — <https://cassandra.apache.org/doc/4.0/cassandra/operating/hints.html>
- Riak, *TicTac Active Anti-Entropy* —
  <https://www.tiot.jp/riak-docs/riak/kv/3.2.0/using/cluster-operations/tictac-active-anti-entropy/>
- Buildbarn `bb-storage` blobstore (mirrored / read-fallback / sharding) —
  <https://github.com/buildbarn/bb-storage>
- BuildBuddy, *Remote Cache CDC: Reusing Bytes* —
  <https://www.buildbuddy.io/blog/content-defined-chunking/>
