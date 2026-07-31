# Backfill (bootstrap simplification) — requirements (draft)

Status: **resolved** — formalized as
[`docs/brainstorms/2026-07-30-kura-backfill-requirements.md`](../../docs/brainstorms/2026-07-30-kura-backfill-requirements.md)
(planning-ready requirements). This file remains the design discussion record
with per-question rationale.

The process currently called *bootstrap* is renamed **backfill**: a node
catching up on a peer's existing data by walking backward from a fixed point,
while live replication (unchanged) covers writes made while the peer is in
view.

## Requirements

1. **Backfill starts on every join/re-join.** A backfill with a peer starts on
   every join/re-join (of either side). It holds an in-memory cursor and walks
   the peer's entries from the newest to the oldest. At most one backfill per
   peer is in flight at a time.

2. **Backfill window.** A backfill covers from the peer's most recent
   `version_ms` down to
   `max(node_backfill_horizon_version_ms, peer_most_recent_completed_backfill_version_ms)`.

   `node_backfill_horizon_version_ms` is the most recent `version_ms` of the
   segment at the configured position in the ring: with segments ordered from
   0 (oldest) to N (most recent) and a configured margin of n%, the segment at
   position N − n%. Example: margin 40%, ring of 100 segments → segment 60.
   The default margin is 40%, which under the 1:2:2 ratio makes the slack
   exactly the new band. The node also keeps, per peer,
   `most_recent_completed_backfill_version_ms`. For a cold node both terms are
   absent, so the window extends to the peer's oldest entry (full backfill).

   The margin gives the bound structural slack equal to the top n% of the
   ring's time span: a peer's absence-window entries are only missed when the
   absence outlasts that span, which folds into the accepted drawback —
   "recent" is guaranteed down to the margin's retention time. The cost is
   that each re-join backfill re-walks the slack window, which the presence
   pre-check keeps to manifest pages (no body transfers).

3. **Restart behavior.** The only state that survives a restart are the
   requirement-2 variables. The in-flight cursor is not persisted: after a
   restart the node re-joins the mesh, which triggers a fresh backfill
   (requirement 1) over a window whose lower bound only advanced if the
   previous pass completed. Entries already applied are skipped by the local
   presence pre-check, so a re-walk costs manifest pages, not body transfers.

4. **Completion condition.** A backfill completes once the cursor reaches the
   window bound, or the peer has no entry older than the cursor position, or
   the segment ring is at capacity and the cursor is older than the oldest
   data still retained (continuing would only fetch entries destined for
   immediate eviction). On completion,
   `most_recent_completed_backfill_version_ms` for that peer is set to the
   start point of the completed pass.

5. **Backfill is a node state, not a peer state.** The node as a whole is
   either backfilling or done backfilling; per-peer cursors are internal
   detail of that single node-level state.

6. **Readiness.** A node is ready when its segment ring is at least X% full
   (count of segments against the ring's desired total) or it is no longer
   backfilling. Segment count is the progress measure because backfill is
   data-transfer limited, and it is node-local — no peer cooperation needed.
   A warm node's ring already satisfies the threshold, so a peer flap or
   re-join backfill can never regress readiness. X is configurable via an
   environment variable; the default is half the backfill window margin
   (requirement 2) — e.g., a 40% margin means the node is ready once 20% of
   the segments are filled.

## Dropped requirements

- ~~Replication restarts at the backfill start point.~~ Dropped: replication
  stays exactly as it works today (outbox enqueued at write time for peers in
  view). Backfill is solely responsible for anything a peer missed while out
  of view.
- ~~Segment limit permanently stops backfilling.~~ Dropped: the backfill
  window (requirement 2) already bounds how much data a re-join pulls, so
  recent data is not at risk of being evicted by backfill volume — unless
  peers hold completely disjoint datasets, which is not the expected shape of
  the mesh. A permanent stop would also have blocked re-join gap backfills
  (recent data the node genuinely wants) on any node whose ring ever filled.

## Accepted drawbacks

- It is possible that not all entries end up backfilled; the design guarantees
  the recent ones will be.

## Scenarios covered

- **Nodes restarting** due to version bumps or minor network blips: they are
  either still backfilling (a fresh pass re-covers the window cheaply) or they
  catch up fast through replication.
- **Nodes added to the mesh** — mainly new region nodes: they are cold and
  backfill properly.
- **Nodes temporarily added to the mesh** — runners' co-located nodes: they
  are cold and backfill properly.

## Technical direction

- Segments are split into three bands — **old**, **current**, and **new** — at
  a 1:2:2 ratio of the segment budget (this already exists:
  `src/segment/state.rs`, ratio resolved in `resolve_segment_ring_limits`).
  All writes land in the active segment (`new.last()`); sealed segments
  cascade new → current → old, and eviction unlinks from the front of `old`.
- **Transfer protocol (bulk, two phases — initial idea, to be refined).**
  Phase 1: one paginated request per peer returning the
  `(version_ms, artifact_id)` pairs the peer holds, newest-first — the same
  shape as the action-cache snapshot index (newest-first listing with a
  write-time watermark for deltas), but backed by a persistent
  `version_ms`-ordered secondary index so it can paginate the full dataset
  rather than a capped in-memory scan. Phase 2: match the pairs against local
  entries and bulk-request only the missing bodies. Pair matching and
  cross-peer dedup happen at this level: a `(version_ms, artifact_id)` pair
  already requested from one peer is not requested from another. The
  pair/dedup working set may be stored in RocksDB or files; whatever the
  medium, it must adhere to the node's memory constraints.

  Bulk batches are **bounded by bytes, not count** (Bazel produces thousands
  of small artifacts and hundreds of thousands of action-cache entries), and
  are **spooled through the filesystem on both ends** — memory is reserved
  for serving user requests, not for this path. The sending peer appends
  records to a temp file until the byte threshold is reached, closes it, and
  sends it over; the requester drives pagination by providing the cursor
  (`artifact_id` + `version_ms`). The receiving node writes the incoming
  batch to its temp folder and processes it from disk. Artifacts too large
  for the batch threshold are fetched individually through the existing
  artifact download endpoint. Temp usage on both sides falls under the
  existing tmp-budget accounting.
- The merged walk is globally newest-first (recency-ordered): if a backfill
  is cut short — restart, capacity completion — the entries that made it in
  are the most recent ones.
- **Join/leave detection already exists.** The membership loop computes
  `discovered_peers` / `lost_peers` on every tick
  (`apply_membership`, `src/state.rs`); each discovered peer is the backfill
  trigger (initial discovery reports every peer as discovered, so process
  start needs no separate trigger).
- Backfill writes go into the live active segment (`new.last()`), exactly like
  replication and client writes — no dedicated backfill segments. Physical
  eviction order for backfilled data is therefore not age-correct; read-path
  promotion compensates for entries that are actually used.

## Resolved questions

- **Sync-bound term.** Initially flagged as overshooting in the
  peer-was-absent scenario. Resolved: the term is the newest `version_ms` of
  the segment at a configurable percentile position in the ring (default 40%
  from the top — the new band under the 1:2:2 ratio), so the bound carries
  that fraction of the ring's time span as slack; entries are only missed
  when an absence outlasts it, which the accepted drawback covers. See
  requirement 2.

- **Cold node smaller than the dataset.** Resolved: the completion condition
  (requirement 4) gained a capacity clause — the backfill also completes when
  the ring is at capacity and the cursor is older than the oldest retained
  data. Per-pass, so re-join gap backfills (recent data) on a full node still
  run. Implementation note: "oldest retained data" must be judged by data age
  (`version_ms`), which requires recording a min/max `version_ms` stat per
  segment at seal time — `created_at_ms` on `SegmentReference` diverges from
  data age precisely because backfill writes into the active segment.
- **Placement of backfill writes.** Resolved: the live active segment
  (`new.last()`), today's behavior — zero store changes, no second open
  segment. Eviction order for backfilled data is not age-correct; accepted,
  with read-path promotion compensating for entries that are used.

- **Readiness measure.** Resolved: ring-fullness (segment count vs desired
  total) rather than dataset-percentage — node-local, cheap, and immune to
  readiness regression on peer flaps. Configurable via env var; default is
  half the backfill window margin (margin 40% → ready at 20% ring fullness).
  See requirement 6.
- **Bulk body fetch framing.** Resolved: byte-bounded batches spooled through
  temp files on both ends (never held in memory), requester-driven pagination
  by `(artifact_id, version_ms)` cursor, oversized artifacts via the existing
  per-artifact download endpoint. See the transfer protocol in Technical
  direction.

## Open questions

None currently.
