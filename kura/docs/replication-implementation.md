# Kura replication redesign — implementation log

Companion to [`replication-design.md`](replication-design.md) (the design) and
[`replication-test-plan.md`](replication-test-plan.md) (how every change is
re-verified). This file is the running record of the implementation: what is
done, what is in progress, and every design decision that was made or changed
while turning the design into code. It is updated in the same commit as the
change it describes.

Status legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[-]` dropped (reason given).

---

## 1. Tasks

### Phase 1 — store: arrival feed, region watermarks, origin stamping

- [x] T1.1 `sync/fwd/` feed rows written in the same batch as every client
      write, region-sync apply and namespace delete (kind, record_id,
      version_ms, size, arrived_at_ms); persisted monotonic `seq`; echo rule
      (no row for a change that arrived from the sibling or applied nothing).
- [x] T1.2 Incarnation minted once at store creation, persisted under
      `sync/fwd/meta/incarnation`.
- [x] T1.3 Feed activation by the first same-region `{head}` request; off
      after the stale-peer window with no sibling listed; range-delete trim
      below the consumer cursor with an explicit floor meta value; cap with
      drop-oldest (`KURA_SYNC_FEED_MAX_ROWS`, default 1,000,000).
- [x] T1.4 `origin_region` on manifests (additive), stamped at first write,
      carried through replication and backfill frames; unknown origin listed
      by everyone.
- [x] T1.5 Region watermarks under `sync/wm/{region}`, merged by max; seeded
      from the old `backfill/wm/` rows; watermark advances written as feed
      rows (kind `watermark`).
- [x] T1.6 Ascending `version_ms` index read from a watermark, origin-filtered,
      with the page cursor as the full key.
- [x] T1.7 Sync scans use `fill_cache = false`.

### Phase 2 — endpoints

- [x] T2.1 `GET /_internal/sync/forward?after={inc}:{seq}&wait=30s` with the
      four-case contract (`{entries,next,head}` / `{head}` + watermark map /
      `410 {floor,head}` / `410` on a foreign incarnation); long-poll wakes on
      commit.
- [x] T2.2 `GET /_internal/backfill/entries` gains `now`, `order=asc`,
      `from_version_ms`, `origin_region` filtering.
- [x] T2.3 `/_internal/status` reports `region` (already), `traffic_state`,
      `pulling` (the flip capability) and `incarnation`.

### Phase 3 — pullers

- [x] T3.1 Replica sync task per same-region peer: snapshot `{head}` →
      horizon-bounded backward pass → forward reads; cursor persisted per
      `(peer, incarnation)`; bodies through the existing backfill fetch/apply
      pipeline; page advances only when every entry is applied/declined/absent.
- [x] T3.2 `410` / missing cursor → snapshot, backward pass, forward.
- [x] T3.3 Region sync task per remote gateway (gateway role only): ascending
      forward reads from the per-origin watermark, capacity rule per entry,
      settle guard, backward pass with the pass-start buffer on
      enter/leave/restart/promotion.
- [x] T3.4 Watermark adoption from `{head}` after the backward pass completes.

### Phase 4 — roles and the flip

- [x] T4.1 Local role derivation (serverless rule) from the membership view:
      group Ready non-draining peers by region, gateway = lowest node URL,
      overlap over gaps.
- [x] T4.2 Server publishes `peer_roles: [{url, region, gateway}]` beside
      `peers` in heartbeat and peers-sync responses; managed roles come from
      `KuraInstance.status.peerRoles`; enrolled self-hosted roles from the
      lowest-URL rule.
- [x] T4.3 kura-controller publishes `status.peerRoles` (complement of the
      primary, Ready and non-draining, lowest ordinal tie-break) and pins the
      instance's public peer Service to the gateway pod.
- [x] T4.4 The flip: `KURA_REPLICATION_PULL` env / server account flag
      (`kura_replication_pull`), advertised as `pulling` in `/_internal/status`;
      per-peer rule (pull from pulling peers by role, push to the rest).
- [x] T4.5 Provisioner renders the flag into `extraEnv` and the manifest
      revision; peers sync enabled for every mesh region.

### Phase 5 — lifecycle rules

- [x] T5.1 Drain gate: wait for the sibling cursor to reach head, bounded by
      the termination grace period less a margin; Helm value.
- [x] T5.2 Readiness follows the sibling (bootstrap settled + forward cursor
      within one page); region of one keeps today's rule.
- [x] T5.3 Serve-side gate (INV-6) for young action-cache entries.
- [x] T5.4 Bandwidth limiter bypass for same-region peers.

### Phase 6 — observability and docs

- [x] T6.1 Metrics of design §6.2 plus panels in
      `infra/grafana-dashboards/tuist-kura-details.json`.
- [x] T6.2 `architecture.md`, `README.md`, `ops/` values, `AGENTS.md` updated.

### Phase 7 — tests

- [ ] T7.1 Unit tests for every store/endpoint/puller rule above.
- [ ] T7.2 shellspec e2e: `sync_spec.sh` (two replicas + two regions on
      compose), pull flip, drain gate, feed fall-off recovery, mixed-version
      (push peer) mesh.
- [ ] T7.3 k01 clusters: every setup in the test plan.

### Phase 8 — measurement and delivery

- [ ] T8.1 main vs branch comparison (memory, disk, CPU, network) per setup.
- [ ] T8.2 Draft PR.

---

## 2. Design decisions made during implementation

Numbered `D-n`. Each records what the design said, what was done, and why.
A decision that changes the design also updates `replication-design.md`.

**D-1 — Pushed applies earn a feed row; sibling applies never do.** The
design's echo rule names "a change that arrived from the sibling — by either
sync direction, or by an old-version sibling's push". A push on the legacy
routes does not say which region it came from, and it may have crossed a
region boundary, so it is treated as cross-region: it writes a row. This
cannot loop, because an apply that arrived over the feed writes no row on the
receiving side, and a same-region old-binary pusher never reads the feed (the
feed is off until a pulling sibling asks). In a two-replica region the row is
never even written; with more replicas it costs one redundant delivery that
last-writer-wins absorbs. `ApplyProvenance` carries the decision on every
replicated apply.

**D-2 — A cursor above the head is `410 ahead`.** Rows are visible to a
sibling before the WAL fsync that makes them durable, so a crash can lose a
tail the sibling already consumed and restart the counter below the sibling's
cursor. Instead of tracking durability per row, the source answers `410` for
any cursor above its head; the sibling takes a fresh snapshot and runs the
backward pass, which covers the lost tail. Same recovery as the floor case,
no new mechanism.

**D-3 — The forward request names the requester.** `peer` (its node URL) and
`region` ride the query. The region is checked (the feed is intra-region
only) and the peer keys the consumer cursor used for trimming and the drain
gate. The design's request shape did not say who was asking.

**D-4 — Region watermarks are seeded lazily by the region task.** The seed
value is the highest `backfill/wm/` row among the nodes the membership view
places in that region, taken the first time the task needs a watermark it
does not have.

**D-5 — The origin filter is a manifest lookup, not an index-row field.** The
`backfill/idx/` value is exactly eight bytes and an older binary rejects any
other length, so widening it would break the listing under rollback. The
ascending read looks the origin up per row (manifest cache first); the cost
is bounded by the page and paid only by forward region reads.

**D-6 — Ascending reads carry a settle guard.** A record's `version_ms` is
stamped before its batch commits, and batches commit in any order, so a
puller that lists up to the newest committed entry can skip a lower entry
whose batch is still landing. The serving node never lists an entry younger
than `now − KURA_SYNC_REGION_SETTLE_MS` (default 2 s). This is the ascending
read's equivalent of the feed's contiguous head.

**D-7 — The server publishes roles for managed regions only.** For enrolled
self-hosted nodes the server would apply the same lowest-URL rule the nodes
already apply locally, so publishing adds nothing; managed regions are where
the server has information the nodes lack (the primary). A published role is
used only when the node it names is present as a pulling candidate;
otherwise the local rule decides, which is what gives overlap over a gap.

**D-8 — Long-poll wait defaults to 25 s.** The peer client's idle read
timeout is 30 s and every internal request shares that client; a 30 s hold
would race it. The parameter table's 30 s becomes 25 s
(`KURA_SYNC_LONG_POLL_SECS`). Idle polls re-check every second, bounding a
missed wake.

**D-9 — Forward pages apply as one backfill pass each.** The existing pass
pipeline (claim set, byte-bounded bodies batches, group commits) is reused
by handing it the page's entries instead of a listing walk, and the cursor
advances when the pass completes. Fetching page N+1 while page N applies is
lost; on a long-poll link pages are small, and a catching-up sibling is
bounded by loopback, so the simplicity wins. Pipelining across pages is the
first optimisation to revisit if the lag gauge says otherwise.

**D-10 — Feed activation persists across restarts.** The design switches the
feed on at the first `{head}` request. A restart must not silently switch it
off while a sibling is still reading forward, so the flag is a marker row
(`sync/meta/enabled`) and the feed comes back on as it was. Deactivation
(no consumer for the stale-peer window) clears it.

**D-11 — Feed keys live under `sync/fwd/`, markers under `sync/meta/`.** The
design wrote `sync/fwd/meta/incarnation`; a marker inside the row prefix
would sit inside every row scan. Same column family, same rollback story.

**D-12 — After a backward pass, the region watermark advances to the peer's
clock at pass start, less the buffer.** The design advances it "on
completion" without saying to what; the listing carries no origin per row,
so "highest own-origin `version_ms` shown" is not observable from a
backward pass. The serving gateway sits in the origin region, so its `now`
(read from a one-row probe before the pass) is that region's clock domain,
and `now − buffer` is below any record that could still be in flight to it
(the same intra-region-lag assumption §4.4 already makes). INV-1's point —
never the puller's clock — holds. A peer that sends no `now` (an older
binary) leaves the watermark where it was.

**D-13 — A snapshot pins the trim floor but not the drain gate.** The
`{head}` request registers the sibling's position so the rows above it
survive its backward pass, exactly as a forward cursor would; the drain gate
ignores it, because the design says a mid-bootstrap sibling is not waited
for. `FeedConsumer.pinned` carries the distinction.

**D-14 — The ascending read always returns its page cursor.** With the
cursor only present when a page was full, a caught-up requester had no way
to continue past the newest row it was shown and would have re-listed it on
every poll; with it present whenever the scan moved, the requester keeps it
across long-polls and resumes from the watermark only after a failure. A
page with neither entries nor cursor is the "caught up" signal the server's
long-poll waits on.

**D-15 — Roles are re-derived on every membership tick, links follow.** The
coordinator diffs the desired links (siblings; remote gateways when this
node is the gateway) against the running tasks and opens or cancels the
difference. A role move therefore costs one cancelled pass and one new
bootstrap on the new holder — the "brief pause" §2.1 budgets for.

**D-16 — The legacy scheduler steps aside per peer.** Peers that advertise
pulling are removed from the backfill lifecycle's view (never passed over,
never part of its initial cycle) while this node pulls; peers that do not
keep today's passes and pushes. Readiness combines both: the legacy cycle
settled *and* the pull links settled (§3.6), or the ring-fullness escape.

**D-17 — INV-6 needed no new code.** `GetActionResult` already inspects every
referenced blob's presence before answering (`inspect_action_result_blobs`,
the composite presence gate that #12937 extended to chunk recipes) and
answers `not_found` when one is gone, deleting the entry only past the
cascade grace window. That is exactly §3.3: serving is gated on the blobs,
ordering is an optimisation. The task is closed against the existing path;
the ring-A test for it is the existing `snapshot_serve_cascade_*` coverage.

**D-18 — The peer Service of a managed region is pinned to the gateway pod.**
The instance's public peer Service selected every pod, so a remote gateway's
listing pages could alternate between the two replicas. Pinning it to the
gateway (the way the client Services pin to the primary) makes the served
listing one node's, keeps both directions of the region's WAN traffic on the
standby, and doubles as the persisted gateway designation the controller
reads back for stickiness — no new status field for that. The headless
Service keeps the broad selector.

**D-19 — A replica link settles the moment its bootstrap completes.** The
cursor then sits at the snapshot head, which is within one page of the
sibling by construction; waiting for the first forward page would hold
readiness for up to one long-poll wait with nothing to show for it.

