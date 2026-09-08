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

- [x] T7.1 Unit tests for every store/endpoint/puller rule above.
- [x] T7.2 shellspec e2e: `sync_spec.sh` (two replicas + two regions on
      compose), pull flip, drain gate, feed fall-off recovery, mixed-version
      (push peer) mesh.
- [x] T7.3 k01 clusters: every setup in the test plan.

### Phase 8 — measurement and delivery

- [x] T8.1 main vs branch comparison (memory, disk, CPU, network) per setup.
- [x] T8.2 Draft PR.

### Phase 9 — follow-ups from review (design §11), required before the flip

- [ ] T9.1 Hard upload limits as explicit config: per-peer bodies slot count,
      per-node peer-serving aggregate; `rejected_busy` and the limiter's
      effective rate on the dashboard row (§11.1).
- [ ] T9.2 Push exception for peers that cannot dial back: `/_internal/status`
      advertises the membership view's node URLs; a pulling peer whose view
      does not name this node stays on the push targets. Ring-A test plus a
      ring-B scenario with a peer that cannot reach the pusher (§11.2).

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

---

## 3. Test runs and measurements

Ring A (unit, `cargo test`): 928 passed, 0 failed at commit `0eba194aec`.
Rings B and C are recorded per run below; the comparison of `main` against
this branch is in §3.2.

### 3.1 Ring C runs

**C-1 — self-hosted, no server, 2 regions × 2 nodes (k04, branch image).**
Roles derived locally: exactly one gateway per region (`kura-us-0`,
`kura-eu-0`); each gateway holds one replica link and one region link, each
non-gateway one replica link; feeds active on all four nodes; outbox empty
on every node. A 2,000-write burst of 4 KiB values on the non-gateway
`kura-us-1` converged on the sibling 0.15 s after the last write, on the
remote gateway after 2.8 s and on the remote non-gateway after 5.0 s, with
no sampled miss.

**C-2 / C-4 / C-6 — self-hosted server on k02 with three regions × two
replicas plus a self-hosted node (branch image, pull flipped by env).** The
controller published `status.peerRoles` for every instance (primary
ordinal 1, gateway ordinal 0 — the complement); the nodes derived one
gateway per region (`tuist-kura-0`, `tuist-kura-eu-0`, `tuist-kura-ap-0`),
the gateway clique (each gateway holds a region link to the other two), and
replica links among every same-region pair, the `local` region running as a
three-node group (two managed replicas and the self-hosted node). Feeds on
everywhere, every link settled in the forward phase. The server did not
publish roles for these instances: this deploy applies its `KuraInstance`s
out of band, so the server has no managed-region rows to read them from
(the published-roles path is covered by the server's unit tests and the
runtime's `published_roles_override_the_local_rule` test).

A 500-write burst of 4 KiB values from the self-hosted node `tuist-kura-sh-0`
(region `local`, non-gateway) converged with no sampled miss on every node:
the local replicas within 0.13 s and 2.4 s, region `eu` within 4.9 s and
7.1 s, region `ap` within 9.6 s and 11.9 s — readers are checked one after
another, so each figure is an upper bound that includes the previous
reader's wait. Outbox 0 on all seven nodes; 1–7 MB of peer traffic per node
for a 2 MB burst; +10 MB on disk per node (the burst plus RocksDB overhead
on nearly empty stores).

**C-5 / C-6 — rollout of the two-replica `local` instance on k02 to a new
image while writing.** The controller rolled ordinal 1 then ordinal 0. The
gateway role stayed on `tuist-kura-0` while ordinal 1 rolled, moved to
`tuist-kura-1` while ordinal 0 was terminating, and returned to
`tuist-kura-0` once it was serving again — the four-move pattern §2.1
budgets for, here two moves because the standby rolled first. A 600-write
burst from the self-hosted node during the roll converged on both replicas
(0.12 s / 2.4 s after the burst) with no sampled miss.

The drain gate itself, on the drain-fixed binary: a `SIGTERM` sent to the
standby `tuist-kura-1` in place (its sibling live and caught up) exited the
process 3 s later with `sibling cursor reached the head before exit`, and
the restarted container was serving again 30 s after the signal with both
of its replica links forward and settled — the "normally nothing" case of
§3.5, as observed. (The controller's own rolls recreate the pod, so their
departing containers' logs are not retained; the e2e drain scenario B-4
covers the lagging-sibling case with timings.)

**C-3 — a self-hosted node in a second cluster enrolling with the k02
server: not reproducible in this lab.** Enrollment answers
`503 ca_unavailable` because the self-hosted deploy has no provisioned
region whose peer CA the server could sign with (`Mesh.read_account_peer_ca`
walks `kura_servers`, which the out-of-band deploy never creates). The
scenario is the hosted provisioning path itself, exercised in production
by every enrolled self-hosted node; what this branch adds to it —
`peer_roles` and `replication_pull` in the heartbeat — is covered by the
controller tests in `server/test/tuist_web/controllers/internal/kura_mesh_controller_test.exs`
and by the runtime's heartbeat decoder.

**C-7 — mixed versions on k04: region `us` on the branch image with pull
on, region `eu` on the `main` image.** The `us` nodes derived their roles
(one gateway, one replica link each, no region link — the `eu` nodes do
not advertise pulling, so they stay push targets), the `eu` nodes ran
unchanged. A 1,000-write burst from `kura-us-1` reached `kura-us-0` in
0.13 s, `kura-eu-0` in 2.7 s and `kura-eu-1` in 5.0 s; the reverse burst
from `kura-eu-1` reached `kura-eu-0` in 0.12 s, `kura-us-0` in 2.4 s and
`kura-us-1` in 4.9 s; no sampled miss either way, outbox empty on the
branch nodes after both bursts. This is the ship/flip compatibility the
migration plan (§5.2) rests on.

**C-8 — volume rebuild on k04 (branch image).** Deleting `kura-us-1` with
its volume brought it back with a new incarnation
(`db6441c870006b1e` → `667aeb3259e0e794`); its sibling `kura-us-0`
recorded exactly one `kura_sync_forward_fell_behind_total{reason="incarnation"}`
and re-bootstrapped, and the rebuilt node's own replica link was forward and
settled with `/ready` answering 200 five seconds after the pod was Ready.

### 3.2 `main` vs branch, same cluster, same burst

Serverless mesh on k04, 2 regions × 2 nodes, one VM (6 vCPU / 12 GB), writer
`kura-us-1`, 2,000 sequential 4 KiB key-value writes issued from inside the
writer pod (so the writer's CPU column includes 2,000 `curl` processes on
both sides). Deltas are cAdvisor counters over the run; the data directory is
`du` of the volume. Convergence is the time from the last write until the
last key is readable on each other node.

| image | pod | role | cpu s | tx MB | rx MB | working set MB | data dir MB | converged after burst |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| branch | kura-us-1 | writer, non-gateway | 15.4 | 12.4 | 1.5 | 18 → 24 | 21 → 43 | — |
| branch | kura-us-0 | us gateway | 4.2 | 14.1 | 14.5 | 19 → 25 | 21 → 43 | 0.15 s |
| branch | kura-eu-0 | eu gateway | 4.8 | 15.9 | 15.8 | 20 → 26 | 21 → 43 | 2.8 s |
| branch | kura-eu-1 | non-gateway | 2.8 | 2.5 | 13.2 | 18 → 23 | 21 → 43 | 5.0 s |
| main | kura-us-1 | writer | 20.1 | 33.9 | 1.5 | 11 → 22 | 0 → 24 | — |
| main | kura-us-0 | — | 1.6 | 0.6 | 11.4 | 11 → 16 | 0 → 21 | 0.11 s |
| main | kura-eu-0 | — | 1.2 | 0.6 | 11.3 | 11 → 16 | 0 → 21 | 2.4 s |
| main | kura-eu-1 | — | 1.6 | 0.6 | 11.4 | 10 → 17 | 0 → 21 | 5.0 s |

| branch (fresh) | kura-us-1 | writer, non-gateway | 17.0 | 12.5 | 1.6 | 10 → 19 | 0 → 21 | — |
| branch (fresh) | kura-us-0 | us gateway | 4.7 | 14.7 | 14.8 | 11 → 21 | 0 → 21 | 0.27 s |
| branch (fresh) | kura-eu-0 | eu gateway | 4.8 | 15.8 | 15.7 | 11 → 20 | 0 → 21 | 3.4 s |
| branch (fresh) | kura-eu-1 | non-gateway | 3.4 | 2.6 | 13.4 | 11 → 19 | 0 → 21 | 7.2 s |

Reading it (the first four branch rows are a warm second run on the same
volumes, so their "before" columns start higher; the "fresh" rows are a
redeploy on empty volumes like the `main` run, taken while the host was also
building images, which is why that burst took 105 s instead of 75 s):

- **Egress moves off the writer.** The writer's transmit falls from 33.9 MB
  (three pushes of the burst) to 12.4 MB (one feed read by its sibling); the
  cross-region bytes are carried by the two gateways instead, which is the
  design's intent (§2). Total bytes on the wire are higher on the branch
  (44.9 MB against 35.7 MB across the four pods): a record now crosses three
  hops (feed → region read → feed) with a descriptor page and a bodies frame
  per hop, where push sent three direct copies.
- **CPU moves the same way.** Writer CPU 20.1 s → 15.4 s (both include the
  2,000 `curl` processes); receivers 1.2–1.6 s → 2.8–4.8 s, since a puller
  lists, presence-checks and applies where a pushee only applied. Sum over
  the four pods: 24.5 s → 27.2 s.
- **Convergence is within a second or two of `main`** on every hop for a
  burst the writer paces at ~20–27 writes/s; the remote-region hop carries the 2 s settle
  guard (D-6) plus one long-poll wake, the remote replica one more feed hop.
- **Disk is the same** (+21 MB per node for the burst on both images; the
  feed rows are trimmed behind the sibling's cursor). Working set after the
  burst: 16–22 MB on `main`, 19–21 MB on the branch.
- **Outbox is empty on every branch node** during and after the burst; on
  `main` it drains to zero as well at this rate — the difference shows under
  a slow or absent peer, which ring B's fall-off scenario (B-3) and the
  10k-writes-while-stopped scenario (B-2) cover.

**Stalled peer, both images (k04, 2 × 2, the `eu` gateway's process
frozen with `SIGSTOP` for the whole burst, 1,500 × 4 KiB writes on
`kura-us-1`).** On `main` the writer's outbox held 1,500 messages for the
frozen peer at the end of the burst (one per write — L2's coupling), the
other three nodes converged as usual, and after `SIGCONT` the frozen node
took 45 s to catch up while the writer drained its queue to it one message
at a time (476 still queued when the last key arrived). On the branch the
frozen gateway's sibling `kura-eu-1` took the `eu` gateway role within a
tick and converged through its own region link during the stall
(overlap over gaps, §2.4), and the frozen node caught up 1.5 s after
`SIGCONT` by resuming its region read from its watermark. The same run
found that a pulling peer which drops out of the membership view was
being pushed to again while unreachable (955 queued rows on the branch
writer, pruned rather than delivered once the peer returned pulling);
fixed by remembering a peer's last advertised pull flag across its absence
(D-20). Re-run with the fix: writer outbox 0 throughout the stall, the
same convergence on the live nodes, and the frozen node caught up 1.6 s
after `SIGCONT`.

### 3.3 Ring B (docker compose)

`spec/e2e/sync_spec.sh` at the drain-gate fix commit: 10 examples covering
B-1, B-2, B-3, B-4, B-5, B-6, B-7, B-8, B-9 and B-10. First full run: 9
passed, 1 failed — the drain gate (B-4). Cause: the shutdown sequence told
the internal listener to stop accepting connections before the gate ran, so
the sibling could never report the cursor the gate was waiting for, and the
node exited only when the wait expired. Fixed by running the gate before
the internal listener's shutdown and by shortening long-polls to 250 ms
while draining (the drain wakes them, the sibling re-asks at once with its
new cursor). The pre-existing suites (`discovery_spec.sh`,
`backfill_spec.sh`) pass on the branch: 6 examples, 0 failures, 1 skip
(the opt-in multi-GiB capacity check). After the fix, the drain-gate example
passes standalone with the images rebuilt from the fixed tree (`1 example,
0 failures`; the departing node exits 2.2 s after the paused sibling
resumes, with the "sibling cursor reached the head" line and no timeout),
and the full suite passes: `10 examples, 0 failures` in 139 s.

**D-20 — A peer's pull flag is remembered while it is unreachable.** The
push targets are rebuilt from the membership view, and a peer that stops
answering its status probe leaves the view — which read as "not pulling"
and put it back on push, queueing an outbox row per write for as long as it
was down. The stalled-peer run made this visible. A node now keeps the set
of peers that last advertised pulling (in memory, like the discovered-only
history) and keeps them off the push targets until they come back saying
otherwise; a rolled-back peer that returns with `pulling: false` is pushed
to again from its next tick.

