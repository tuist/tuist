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
      `peers` in the peers-sync response read by managed pods; managed roles
      come from `KuraInstance.status.peerRoles`, observed by the reconciler
      and persisted on `kura_servers` (D-27), so the request path is a
      Postgres read. The heartbeat carries `replication_pull` only: an
      enrolled self-hosted node sees one public URL per managed region, which
      no pod-keyed role can match, so it runs the lowest-URL rule.
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

- [x] T9.1 Hard upload limits as explicit config: per-peer bodies slot count
      (`KURA_SYNC_PEER_BODIES_SLOTS_PER_PEER`), per-node peer-serving
      aggregate (`KURA_SYNC_PEER_SERVING_MAX_INFLIGHT`, derived from the
      membership view unless set); both rejection rates
      and the limiter's effective rate on the dashboard row (§11.1).
- [x] T9.2 Push exception for peers that cannot dial back: `/_internal/status`
      advertises the membership view's node URLs; a pulling peer whose view
      does not name this node stays on the push targets. Ring-A test (A-25)
      plus ring-B scenario B-11 with a peer that cannot reach the pusher
      (§11.2).

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

**D-6 — Ascending reads carry a settle guard.** *(Superseded by D-24 on
any node that carries an arrival feed; it remains the whole rule for a
region of one, which has none.)* A record's `version_ms` is
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

Ring A (unit, `cargo test`): 928 passed, 0 failed at commit `0eba194aec`;
933 passed, 0 failed with phase 9 (A-25, A-26); 943 passed, 0 failed with
D-25 and D-26 (A-29a, A-29b, A-29c), `mise run clippy` and
`mise run format -- --check` clean. Rings B and C are recorded per run below;
the comparison of `main` against this branch is in §3.2.

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
`replication_pull` in the heartbeat — is covered by the
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

With phase 9's B-11 added (the one-way `region-d` pair, images rebuilt from
the tree): `11 examples, 0 failures` in 161 s. B-11 observed what §11.2
predicts — `kura-d1` advertises an empty `peers` list and opens no link,
`kura-d2` names `kura-d1`, pulls its feed and keeps a push leg towards it, a
write on `d1` arrives on `d2` by pull, a write on `d2` arrives on `d1` by
push, and `d2`'s outbox is back to zero afterwards.

**D-20 — A peer's pull flag is remembered while it is unreachable.** The
push targets are rebuilt from the membership view, and a peer that stops
answering its status probe leaves the view — which read as "not pulling"
and put it back on push, queueing an outbox row per write for as long as it
was down. The stalled-peer run made this visible. A node now keeps the set
of peers that last advertised pulling (in memory, like the discovered-only
history) and keeps them off the push targets until they come back saying
otherwise; a rolled-back peer that returns with `pulling: false` is pushed
to again from its next tick.

**D-21 — The push exception is decided from the status exchange, not from a
server field.** Design §11.2's rule needs one bit per pair: can this peer dial
me? `/_internal/status` already carries `region`, `traffic_state`, `pulling`
and `incarnation`, and every node polls it each membership tick, so it gained
`peers` — the node URLs of the view it holds — and `PeerView` gained
`knows_me`, true when that list names this node's own URL (or the gateway URL
it publishes instead, which is how a gateway-fronted node is listed at all).
A server field was the alternative and was rejected: it would not exist in the
serverless mode, would need a matching field under a self-hosted server, and
would describe reachability from a third party's vantage point rather than
from the peer's own. An older peer sends no `peers` at all, which reads as
"does not know me" and keeps it on push — the safe direction, since a
duplicate push into a node that also pulls is absorbed by last-writer-wins for
one feed row (D-1), while the opposite error is a silent gap. The condition
rides along with D-20's sticky set rather than beside it: a peer enters the
set only while it is *pulling and knows me*, so a peer that never could dial
back does not drift off the push targets during an absence, and a peer that
could keeps its exemption exactly as before. `derive_roles` applies the same
condition to `Roles::push_targets` so the coordinator's log field agrees with
the targets the writes actually use.

**D-22 — The peer-serving limits reject, and now say which limit rejected.**
The serving side already refused a second concurrent bodies request per peer
identity, but the count was a hard-coded one and there was no bound at all on
the number of *distinct* peers in flight — the concentration a gateway
actually sees, since every other region's gateway plus its own siblings pull
from it. Both are configuration now
(`KURA_SYNC_PEER_BODIES_SLOTS_PER_PEER`, default 1;
`KURA_SYNC_PEER_SERVING_MAX_INFLIGHT`, which pins the aggregate when set),
rendered by the chart. Unset, the aggregate is derived on every membership
tick as `max(8, visible peers × slots per peer)`: the exact legitimate
maximum is one slot set per counted peer, and the floor of 8 covers the
requesters the view does not count (a peer one tick ahead of it, or one
that dials this node without being dialled back, §11.2). A fixed number
would reject legitimate peers once the mesh outgrew it; twice the peer count
was considered and dropped for the same headroom being unexplainable.
Rejection stays the behaviour: a queue would hold the requester's connection
and the shared tmp budget for an unbounded time, where a `503` with
`Retry-After` lets the pass back off or skip the entry and come back on the
next pass, which the classifier already treats as retryable backpressure. The
aggregate reuses the `peer_busy` error code for exactly that reason — an older
requester must keep classifying it as retryable — and is distinguished only by
the metric label `rejected_node_busy`, so a dashboard can separate one greedy
peer from a saturated node. The limiter's effective rate was already exported
(`kura_replication_bandwidth_effective_limit_bytes_per_second`); it and the
two rejection rates joined the pull replication row of the dashboard.

**D-23 — The bootstrap failure budget is charged per peer, across link
respawns.** The legacy cycle fixes its membership at the first settled tick
and accumulates failure charges per peer for the whole cycle. The pull term
of readiness counted bootstrap failures inside each link task, and the
coordinator cancels and respawns a link whenever its peer leaves and
re-enters the membership view, so a sibling flapping through the status
probe faster than the budget reset its count on every reopen and could hold
`/ready` open on an empty node (the ring-fullness escape still applied to a
warm one). The coordinator now owns one counter per peer, handed to every
task it spawns for that peer and cleared on a successful bootstrap, which
restores the legacy cycle's property without fixing the membership.

**D-24 — The ascending read's guard is a frontier, not a clock offset.**
D-6 assumed every entry a node holds was committed within the settle window
of its stamp. That is true of a node's own writes and false of what it
receives from its same-region sibling: those arrive in page-sized batches
long after their stamp (up to 29 s in Ring D), out of version order, so an
entry can land *below* a remote reader's cursor and never be listed forward
again. §3.4 measured it as a stable 1–9 misses per 200-action seed, and
raising `KURA_SYNC_REGION_SETTLE_MS` on the serving region to 20 s turned
the same read into 200/200 — the mechanism, but not a fix: the right
constant is the sibling's worst delivery lag, which is unbounded.

The guard is now exact, in three parts.

*One stamp per record.* The feed allocates its seq and reads the wall clock
together under the in-flight lock, carries that stamp on the ticket, and
uses it as the row's `arrived_at_ms`. A write this node generates takes its
`version_ms` from the same stamp instead of a separate `now_ms()` at spec
build: `PersistArtifactSpec::server_stamped` marks those sites, their
`version_ms` is `0` until staging resolves it, and the two prechecks compare
at the clock instead (below the stamp staging will give it, so the
last-writer-wins and tombstone gates stay conservative). A client-supplied
version and a replicated apply keep the version they arrived with; a local
namespace delete is stamped like a write, which means it holds its ticket
across the namespace scan — deletes are rare enough for that to beat a
tombstone the frontier cannot bound. `created_at_ms` follows `version_ms` as
it always did, both being `persisted_version_ms` of the same value.

*The frontier.* `SyncFeedState::frontier_ms` is the stamp of the lowest
in-flight seq, or `now` when nothing is in flight. Because stamps order like
seqs, every server-generated record with `version_ms < frontier_ms` has
committed and is in the index. It rides both forward responses as an
additive `frontier_ms`, and the replica link keeps the last one it was told
per link: the snapshot's at bootstrap; the page's when a page leaves it
caught up; the last applied entry's `arrived_at_ms` when it does not, since
every row above that one carries a stamp at least as high.

*The bound.* `SyncCoordinator::listing_bound` is the minimum of the feed's
own frontier (or `now − settle` where there is no feed — a region of one is
unchanged) and every open replica link's frontier, each exclusive, and the
ascending read serves `min(now − settle, bound)`. A link that is
bootstrapping, or that has settled and never reported, bounds everything:
the listing waits rather than skipping a version that link may still
deliver. That is deliberate — a stalled sibling pauses cross-region delivery
instead of losing it — and `kura_region_listing_bound_lag_seconds` is what
makes the pause visible. The one link that does *not* bound is one whose
bootstrap budget is spent, which has stopped delivering altogether (D-25). A
peer too old to send a frontier leaves the link on the rows' own stamps, and
on its clock when a caught-up page carries no rows, which is the
settle-window exposure D-6 already had.

One consequence had to be paid for: the bound only moves when a response
carries a fresh frontier, so an idle sibling holding a 25 s long poll would
have left a gateway's own writes unlistable for that long. The replica
link's forward `wait` is therefore capped at the settle window. A committed
row still returns the instant it lands — the cap changes nothing about row
latency — and it costs one idle request per window on loopback. The region
link keeps the full `KURA_SYNC_LONG_POLL_SECS`; only the loopback link pays.

D-6 stands only where there is no feed. Ring A covers the pieces as A-28a–d
plus the three-node link case; §3.5 is the fleet rerun.

### 3.4 Ring D — sustained REAPI load on k02 (2026-09-08)

The first run that drives the mesh through the REAPI surface for a sustained
stretch rather than with a key-value burst. Fresh cluster `k02`
(3 microVM nodes, 12 vCPU / 24 GB total), everything built from this branch
(`kura-runtime` digest `sha256:4095a3c8…`, confirmed on all five pods), the
server in **hosted** mode (`TUIST_HOSTED=1`).

Topology: region `local` with two managed replicas plus the self-hosted
stand-in (`tuist-kura-sh`, 1 replica — a real cross-cluster enrollment is still
not reproducible here, §3.1 C-3), and region `eu` with two managed replicas
behind its own public host. `KURA_REPLICATION_PULL=true` on every instance.
Before the run: one gateway per region (`tuist-kura-0`, `tuist-kura-eu-0`), the
gateway pair holding the only cross-region link, replica links among every
same-region pair, every link `forward` and `settled` with `lag_entries` 0, feeds
enabled, outbox 0 on all five pods.

Load: 8 iterations at a 75 s period, `--jobs=4`, 200 `genrule`s per build
(68.3 MiB of incompressible payload), alternating regions —
**3,000 actions over 541 s = 333 actions/min**, 546 MiB written, 478 MiB asked
for on the read side. Every Bazel invocation exited 0.

| pod | node | CPU s | peak CPU | mean/peak WS MB | rx MB | tx MB | data dir MB | max outbox | max fwd lag |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tuist-kura-0 (gw local) | k02-0 | 21.6 | 11% | 38 / 59 | 570 | 828 | 811 → 1359 | 0 | 0 |
| tuist-kura-1 | k02-0 | 18.9 | 14% | 44 / 61 | 570 | 775 | 746 → 1294 | 0 | 0 |
| tuist-kura-sh-0 | k02-0 | 17.1 | 7% | 39 / 50 | 565 | 16 | 754 → 1301 | 0 | 0 |
| tuist-kura-eu-0 (gw eu) | k02-2 | 19.7 | 9% | 62 / 83 | 563 | 555 | 735 → 1275 | 0 | 0 |
| tuist-kura-eu-1 | k02-2 | 18.0 | 13% | 42 / 65 | 565 | 558 | 670 → 1211 | 0 | 29 |

Per-iteration read hit rates (each read asks the region that did *not* write the
seed, ~75 s after it was written): 96%, 98%, 98%, 100%, 96%, 98%, 98% —
1,366 of 1,400 actions. Write builds took 14–16 s, read builds 0.8–1.3 s.

**What the run establishes.**

* Steady state holds. Outbox 0 at all 60 samples on all five pods; every link
  `forward`/`settled` before and after; forward cursor lag 0 everywhere except
  a single 29-entry sample on `tuist-kura-eu-1`; `gateway_role_changes` and
  `peer_connection_failures` did not move; no capacity shed of any kind and
  memory pressure 0 throughout (D-1, D-3, D-6).
* Cross-region convergence is prompt. `kura_region_watermark_age_seconds` is a
  clean sawtooth: it climbs while the other region is idle and resets to **5–8
  s** within one sample of that region's write finishing, on both gateways, for
  every one of the eight iterations — it never ratchets. Region sync cycles
  succeeded continuously (`region_sync_last_success_age_seconds` ≤ 29 s) (D-2).
* Replication is not a bottleneck at this rate. Every pod grew by 541–547 MiB
  against 546 MiB of payload, so each node took the whole dataset regardless of
  which region ingested it, at a peak of 14% of one core and under 85 MB of
  working set (D-4, D-6).
* Client traffic and the peer plane separate cleanly: the REAPI artifact
  counters moved only on `tuist-kura-1` and `tuist-kura-eu-1`, so in both
  regions the public Service served from the non-gateway replica and the
  gateways carried peer traffic only.

**What it does not establish — a persistent cross-region gap.** *(Diagnosed as
the settle-guard defect, fixed by D-24, re-measured in §3.5.)*
D-5 fails. Reading a seed back from the region that did not write it returns
the *same* hit count long after the mesh is quiescent as it did during the run
(193/197/195/199/191/195/196 in-run, byte-identical in `verify.csv`), so the
1–9 misses per iteration are not lag. Reading one seed from its origin region
gives 200/200 on repeat; from the other region it gives 191/200 on repeat.
It reproduces without any load at all: a single 200-action write into `local`
on an otherwise idle mesh reads back 195/200 from `eu` after 2 minutes and
still 195/200 after 6 minutes, while the same seed reads 200/200 from `local`.
The miss is not size-correlated (1 miss in the twenty 2 MiB targets, 0 in the
twenty 768 KiB, 1 in the twenty 8 KiB). Consistent with it,
`kura_manifest_index_entries` settles at 12,793 on both `local` replicas and
12,785 on both `eu` replicas — a stable 8-entry deficit — with
`kura_sync_forward_index_dropped_total` 0, every `replication_requests_total`
outcome `ok`, no `action_cache_cascade_removed`, outbox 0 and every link
`forward`/`settled`.

Ruled out before recording it as a defect: a client-side upload failure (the
origin region serves the same seed 200/200, and no Bazel invocation logged a
warning); a single lagging replica (both `eu` pods report the identical index
count, and the miss set is deterministic across runs that open four
connections); capacity or memory (all shed counters 0, pressure state 0, 1.3 GB
used of a 10 GiB volume); and saturation (it reproduces on an idle mesh). What
is still unknown is whether the missing item is the AC manifest or a referenced
CAS blob, and why the health signals report converged while it is absent.

#### Ring D, batch 2 — restarts and stop/resume (2026-09-08)

Same cluster, same image and the same load as batch 1
(`run-load.sh k02 600 75 4`, 200 targets, 8 iterations, alternating regions,
546 MiB of payload), with the chaos sequence from the test plan injected into it.
`t0` = 2026-09-08 23:46:18 UTC. Baseline before the run: five pods Ready with 0
restarts, one gateway per region (`tuist-kura-0`, `tuist-kura-eu-0`), every link
`forward`/`settled` with `lag_entries` 0, outbox 0 on all five, and the client
Services pinned to the non-gateway replica of each region (`tuist-kura` →
`tuist-kura-1`, `tuist-kura-eu` → `tuist-kura-eu-1`).

| event | offset | readiness / role | links, outbox | overlapping iterations | recovery |
| --- | --- | --- | --- | --- | --- |
| E1 delete `tuist-kura-1` (local client-serving pod) | +2:00 | Service selector on `tuist-kura-0` within 13 s; pod recreated 23:48:41, Ready 23:49:09 (51 s); no role change | one 5 s sample with the recreated pod's two replica links `settled=false`, `lag` 0; outbox 0 throughout | none in flight; iteration 3 write 18.19 s (baseline 14.7–16.1 s), rc 0, its read 197/200 | 56 s |
| E2 `SIGSTOP` `tuist-kura-eu-0` (eu gateway) 60 s | +4:01 | `tuist-kura-eu-1` reports `gateway=true` at the first sample after the stop (1 s), `members` 5 → 4; eu-0 NotReady 23:50:52, two liveness failures, **no restart**; `SIGCONT` hit the same pid, role back on eu-0 at 23:51:24, answering `/ready` again at 23:51:18 (the first probe sample after the freeze; probe samples and the injector's clock agree only to ~2 s) | eu-0 unreachable for 4 samples; every reachable link stayed `forward`/`settled`; outbox 0 | iteration 4 read in flight (1.12 s, 200/200); iteration 5 write 19.61 s, rc 0 | 65 s |
| E3 delete `tuist-kura-eu-0` (role holder) | +6:00 | role to `tuist-kura-eu-1` in 6 s; pod recreated 23:52:40, Ready 23:53:01, role back at 23:53:06 | eu-0 unreachable for 7 samples; outbox 0 | none in flight; iteration 6 write 21.68 s (slowest of the run), rc 0, its read 200/200 | 58 s |
| E4 `SIGSTOP` `tuist-kura-sh-0` 90 s | +8:00 | NotReady 23:54:53; **liveness killed the container at 23:55:12** and it restarted 23:55:43 (RESTARTS 1), so `SIGCONT` was a no-op; links settled again 23:56:08; the pod was then deleted at 23:56:01 by an unrelated CPU-band re-template, replaced 23:56:23, Ready 23:56:51 | sh-0 unreachable for two windows; outbox 0 | none in flight; iteration 8 wrote through `eu` 45 s into the freeze, 14.67 s, rc 0, its read 200/200 | 110 s to first settled, 160 s to the final converged state |

Per-pod cost over the 1005 s sample window (deltas are reset-aware, since two
pods were replaced mid-run):

| pod | node | CPU s | mean / peak WS MB | rx MB | tx MB | REAPI r/w MB | data dir MB | max outbox | max fwd lag | gw changes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tuist-kura-0 (gw local) | k02-0 | 26.1 | 44 / 64 | 613 | 2066 | 742.3 / 205.9 | 1978 → 2547 (+569) | 0 | 0 | 0 |
| tuist-kura-1 | k02-0 | 18.1 | 34 / 53 | 569 | 168 | 0.0 / 68.5 | 1913 → 2462 (+549) | 0 | 0 | 0 |
| tuist-kura-sh-0 | k02-0 | 18.3 | 47 / 75 | 605 | 27 | 0.0 / 0.0 | 1923 → 2492 (+569) | 0 | 0 | 0 |
| tuist-kura-eu-0 (gw eu) | k02-2 | 20.8 | 31 / 52 | 573 | 495 | 0.0 / 0.0 | 1889 → 2446 (+557) | 0 | 0 | 2 |
| tuist-kura-eu-1 | k02-2 | 21.6 | 42 / 59 | 586 | 1264 | 818.9 / 274.5 | 1824 → 2377 (+553) | 0 | 0 | 4 |

**What the batch establishes.**

* D-7 holds. Every event was back to a fully converged mesh well inside three
  minutes (56 / 65 / 58 / 160 s), every one of the eight Bazel invocations exited
  0, and no read build took longer than 1.4 s at any point in the run.
* D-9 holds. `kura_sync_forward_drain_timeout_total` stayed 0 on every pod, and
  `kura_sync_forward_fell_behind_total` exported no series at all on any pod at
  any sample — not even the `incarnation` reason, because the replaced pods kept
  their volumes. `kura_sync_forward_index_dropped_total` 0 everywhere.
* Steady state is preserved through the chaos: `kura_outbox_messages` was 0 on
  every pod at all 68 collector samples and all 950 probe samples (193 per pod, every one reading 0), memory
  pressure stayed 0, no capacity shed of any kind fired, and the busiest pod
  peaked at 75 MB of working set. Every pod's data dir grew 549–569 MiB against
  546 MiB of payload — including the two that were replaced (D-4 through chaos).
* Role handover is fast and self-correcting: a frozen gateway lost the role to
  its sibling inside one 5 s probe sample and got it back one sample after
  resuming; a deleted gateway handed over in 6 s and took the role back once it
  was Ready. The role never landed on two pods at once in any sample.
* Client failover works and is sticky: deleting the pinned pod moved the
  `tuist-kura` Service selector to `tuist-kura-0` within 13 s, and it stayed
  there once the replacement was Ready — so `local` served client traffic from
  its own gateway for the rest of the run, which the REAPI byte counters confirm
  (they moved on `tuist-kura-0` and `tuist-kura-eu-1` only).
* Logs are clean: zero `"level":"ERROR"` lines on any pod for the whole window.
  All 110 WARNs are `peer status request failed` against a pod that was down at
  that moment, `/ready` 503 during startup, one `region forward read failed` on
  the frozen node at the instant it resumed, and one `/_internal/sync/forward`
  long poll that ran 79.1 s against a `wait=25` contract while its process was
  frozen.

**D-8 fails, on a known-by-design mechanism.** At 23:56:01 the StatefulSet
deleted `tuist-kura-sh-0` without being asked to. The controller revisions show
revision 3 → 4 changing exactly one field, `requests.cpu` 150m → 250m: this is
`cpu_autosize.go` moving the instance to the next `cpuRequestBands` entry after
the sustained load raised observed CPU, which re-templates the StatefulSet and
rolls its pods (the file's own comment names the trade-off). `tuist-kura` and
`tuist-kura-eu` were already at 250m from batch 1's load, so only the `sh`
instance crossed a band this time. For a `replicas: 1` instance this removes the
region's third copy for ~50 s in the middle of a load test. Nothing to fix in the
replication path; it does mean a Ring D run has to expect a pod replacement it
did not inject.

**D-10 partly holds — and it is the first evidence that a restart repairs the
cross-region gap.** Batch 1's `verify.csv` was byte-identical to its in-run
reads: nothing was ever repaired. Here two of the four short seeds were:

| seed | written via | read from | in run | verify #1 (T+2 min) | verify #2 (all pods stable 3 min) |
| --- | --- | --- | --- | --- | --- |
| d204617-1 | local | eu | 195/200 | 200/200 | 200/200 |
| d204617-2 | eu | local | 197/200 | 200/200 | 200/200 |
| d204617-6 | eu | local | 197/200 | 197/200 | 197/200 |
| d204617-8 | eu | local | not read in run | 197/200 | 197/200 |

The other four seeds read 200/200 in the run and in both verifies. Seeds 1 and 2
were written before the last restart on the side that had to serve them; seeds 6
and 8 were written after it, and stay three actions short — the two verify passes
are byte identical, so they are stuck rather than lagging. That is exactly what
the settle-guard defect predicts (D-24; the
investigation's tooling and evidence are in the harness under
`~/.config/tuist/k01/replication/settle/`): a restarting node runs a buffered
backward pass that recovers records the ascending, settle-bounded read had
skipped, while skips created after the last restart are never revisited. Note
also that every `local` write after E1 went straight to the gateway, and all
three of those seeds (3, 5, 7) read 200/200 cross-region without any repair.

One caveat on batch 1's evidence above: `kura_manifest_index_entries` is
documented in its own HELP text as "Warm in-memory manifest index entries
currently loaded". It read 16,362 on `tuist-kura-sh-0` before this run and 16
after its roll, while that pod's data dir *grew* by 569 MiB — so the 12,793 vs
12,785 split cited earlier measures cache warmth, not whether a record is
present, and should not be read as corroboration of the gap.

Raw data, per-pod logs kept across the rolls, the probe stream and the
controller-revision diff are in the harness repo under
`~/.config/tuist/k01/replication/load/runs/20260908-2045-k02-ringd-chaos/`
(`summary.md`, `findings.md`, `events.md`, `pods.csv`, `iterations.csv`,
`verify1.csv`, `verify2.csv`, `cpu-band-roll.txt`).

### 3.5 Ring D batch 1, rerun on D-24 (2026-09-09)

Same cluster (`k02`, 3 microVM nodes), same topology, same load as §3.4's
batch 1 — 8 iterations at a 75 s period, `--jobs=4`, 200 `genrule`s
(68.3 MiB of incompressible payload each), alternating regions, 3,000 actions
over 540 s = 333 actions/min — with the branch rebuilt to include D-24.

`kura-runtime` digest `sha256:c0437d29…`, verified per pod:

| pod | node | role | image digest |
| --- | --- | --- | --- |
| tuist-kura-0 | k02-0 | gateway `local` | `sha256:c0437d29…` |
| tuist-kura-1 | k02-0 | client-serving `local` | `sha256:c0437d29…` |
| tuist-kura-sh-0 | k02-0 | self-hosted stand-in `local` | `sha256:c0437d29…` |
| tuist-kura-eu-0 | k02-2 | gateway `eu` | `sha256:c0437d29…` |
| tuist-kura-eu-1 | k02-2 | client-serving `eu` | `sha256:c0437d29…` |

The deploy needed two harness fixes, both committed there: the `KuraInstance`
image was a fixed `:selfhost` tag pulled `IfNotPresent`, so containerd's cached
layer kept every pod on the *previous* binary through a full rebuild — the CR
is now applied by digest, which both forces the pull and rolls the sets — and
`deploy.sh` re-applies its own two instance manifests, which silently dropped
`KURA_REPLICATION_PULL` (`regions.sh flip k02 true` restores it, and the
gateway of `local` came back to `tuist-kura-0`).

Before the run: one gateway per region (`tuist-kura-0`, `tuist-kura-eu-0`),
every link `forward`/`settled` with `lag_entries` 0, feeds enabled, outbox 0
on all five pods.

| pod | node | CPU s | mean/peak WS MB | rx MB | tx MB | REAPI r/w MB | data dir MB | max outbox | max fwd lag | max bound lag s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| tuist-kura-0 (gw local) | k02-0 | 22.5 | 41 / 65 | 576 | 851 | 0.0 / 0.0 | 3107 (+560) | 0 | 0 | 26 |
| tuist-kura-1 | k02-0 | 20.2 | 44 / 70 | 578 | 1055 | 478.4 / 274.3 | 3023 (+561) | 0 | 0 | 10 |
| tuist-kura-sh-0 | k02-0 | 17.4 | 40 / 53 | 571 | 16 | 0.0 / 0.0 | 3054 (+562) | 0 | 0 | 28 |
| tuist-kura-eu-0 (gw eu) | k02-2 | 20.5 | 40 / 59 | 575 | 573 | 0.0 / 0.0 | 3016 (+570) | 0 | 0 | 17 |
| tuist-kura-eu-1 | k02-2 | 19.5 | 35 / 58 | 579 | 845 | 546.7 / 274.3 | 2946 (+569) | 0 | 0 | 7 |

(The data-dir deltas are against batch 2's closing figures, the last measurement
these volumes carry; there was no write between the two runs.)

**The defect is gone.**

* Every in-run cross-region read is **200/200**: 7 reads, 1,400 of 1,400
  actions, against batch 1's 96/98/98/100/96/98/98% (1,366 of 1,400).
* `verify.sh` reads all **eight** seeds back from the region that did not write
  them at **200/200**, where batch 1's verify was byte-identical to its short
  in-run reads and never repaired.
* The idle-mesh reproduction from the settle investigation — one 200-action
  write into `local` on a quiescent mesh, read from `eu` two minutes later —
  now returns **200/200** (03:02:45 write, 03:05:07 read). It returned 195/200
  at two minutes and still 195/200 at six before D-24.
* Every Bazel invocation exited 0; write builds 14.1–16.7 s, read builds
  0.8–1.5 s, both in batch 1's range.

**The new gauge shows the mechanism.** `kura_region_listing_bound_lag_seconds`
sits at 0–1 s on every pod while the mesh is quiet, and rises on each gateway
in step with its own region's write burst — peaks of 26 s on `tuist-kura-0`,
17 s on `tuist-kura-eu-0`, 28 s on `tuist-kura-sh-0` — then returns to 0–1 s
within one 15 s sample. That is the replica link's backlog holding the listing
back, and it lines up with the up-to-29 s delivery lag the investigation
measured: those are exactly the windows in which the old `now − 2 s` guard was
listing past records still in flight from the sibling.

**Steady state is unchanged.** Outbox 0 at all 60 samples on all five pods,
forward cursor lag 0 everywhere (batch 1 had one 29-entry sample), every link
`forward`/`settled` before and after, `gateway_role_changes` and
`peer_connection_failures` flat through the run, memory pressure 0, no capacity
shed of any kind, `kura_sync_forward_index_dropped_total`,
`kura_sync_forward_drain_timeout_total` and `kura_sync_forward_fell_behind_total`
all 0/absent, and the busiest pod peaked at 70 MB of working set and 22.5 CPU
seconds over 885 s. Client traffic and the peer plane still separate: the REAPI
byte counters moved only on `tuist-kura-1` and `tuist-kura-eu-1`.

**The watermark sawtooth got slightly tighter.** `kura_region_watermark_age_seconds`
still resets once per iteration and never ratchets; the reset level is now
**3–5 s** on both gateways (batch 1: 5–8 s), which is the settle-window poll
the replica link now runs showing up as a fresher bound. The climb between
resets is the other region's idle period, as before.

Raw data (`pods.csv` with the new `region_listing_bound_lag` column,
`iterations.csv`, `verify.csv`, mesh state before and after, the load log) is in
the harness under
`~/.config/tuist/k01/replication/load/runs/20260908-2345-k02-ringd-d24/`.

---

## 4. Decisions from the review loop (2026-09-09)

**D-25 — A link that has spent its bootstrap budget stops bounding the
listing.** D-24's bound waits on every open replica link, and a link that has
not reported a frontier bounds everything. The ready-but-cold escape (§3.6,
the one the legacy backfill cycle already allows) sets `settled` after
`BACKFILL_INITIAL_CYCLE_FAILURE_BUDGET` failed bootstraps *without* ever
reporting a frontier, and the two together read as a bound of zero: a node
holding an unreachable sibling in its membership view served an empty
ascending listing to every remote region, for as long as the sibling stayed
down, while Ready and serving its own clients normally. The pause D-24 buys
is only worth paying while the link is going to deliver something. A
bootstrapping link is — its backward pass lands records out of version order,
below a remote reader's cursor — so it keeps bounding everything, unchanged.
A link that has given up has stopped: it retries on the pass backoff in the
background, and until one of those succeeds it delivers nothing, so waiting
on it protects nothing and costs every other region its cross-region feed.
The frontier is therefore three states rather than a `u64` in which `0` meant
both "none yet" and "gave up": `LinkFrontier::Pending` bounds everything,
`At(ms)` bounds at `ms − 1`, and `Abandoned` bounds nothing. The budget
escape sets `Abandoned` beside `settled`; the next successful bootstrap sets
`At(snapshot frontier)`, which is the right instant to resume at — the
backward pass that bootstrap just ran delivered everything below it. The
state returns to `Pending` one step earlier than that, the moment a retry's
`{head}` request is answered: from there the backward pass is about to land
records out of version order, which is precisely what the bound exists to
cover, and a retry that never gets an answer lands nothing and keeps the
listing moving. The
trade is the one §4 already takes for the region link: while a sibling is
unreachable a record only it holds can be stepped over by a remote reader
(best-effort, repaired by the next backward pass) instead of the whole
region's listing stopping. Two observability fixes ride along, both needed to
tell this state apart from a healthy pause:
`kura_region_listing_bound_lag_seconds` reported `now − 0` — the epoch in
seconds, some 56 years — whenever the bound was zero, which no panel can plot
beside ordinary lags; it saturates at `REGION_LISTING_BOUND_LAG_MAX_SECONDS`
(86,400) and that ceiling is the "listing bounded whole" reading, documented
on the dashboard panel. And each link row of `/status/cluster` now carries
`frontier` (`pending` / `reported` / `abandoned`) and `frontier_ms`, so which
link is holding the bound is answerable from the node itself. Ring A: A-29c.

**D-26 — An exhausted forward page reports the head.** A feed seq is
allocated before its rows are staged and released when the ticket drops, so
any failure between the two — a failed write batch, a staging error, a
`delete_namespace` that resolves to `IgnoredOlder` — leaves the contiguous
head above the last row on disk. `internal_sync_forward` reported `next` as
the last row's seq, or the requester's cursor when the page had none, so a
page that returned no rows while `head > cursor` reported `next != head`. The
puller read that as "behind", took its frontier from `page.entries.last()`
(`None`, so no refresh at all), and never moved it again; its cursor stayed
below the head too, showing the gap as permanent `lag_entries`. Only the
sibling's next write cleared it — and on a sibling that takes no client
writes (a third replica, or a co-located self-hosted node in the same region)
there is none, so the gateway's serving bound froze at the instant the gap
opened and its own later writes were never listed to any remote region. The
drain gate reads the same stalled cursor (§3.5 waits for every live consumer
to reach the head), so a node with a gap at its head would also have waited
out its whole drain budget on a sibling that was in fact caught up. The
endpoint now reports `next = head` whenever the scan was exhausted (fewer
rows than the limit). That is exactly as safe as reporting the last row's
seq: the scan reached the head, and every seq at or below the *contiguous*
head has resolved by definition, so one carrying no row is an allocation
aborted before staging that no row will ever fill. A full page still reports
its last row, because the scan says nothing about what is above it. The head
is also read once and used for both the scan bound and the response, so a
page can never name a head it did not scan to. Belt and braces on the client:
the puller treats an *empty* page as caught up for frontier purposes whatever
`next` says — sound for the same reason, since every row the sibling holds
above the cursor and at or below its head would have been in the page, and a
row above the head carries a stamp at or after the frontier — which is what
keeps a link to an older sibling moving through a mixed-version rollout. The
persisted cursor stays whatever the server reported: the server owns which
seqs are resolved, and a puller advancing past seqs the server did not
resolve would be inventing that guarantee on its behalf, for nothing the
server fix does not already give it. Ring A: A-29a (the endpoint) and A-29b
(the frozen frontier, end to end over two same-region nodes).

**D-27 — Managed roles are observed by the reconciler, not read on the
request path.** `Mesh.peer_roles/1` answered `/_internal/kura/mesh/peers`
and the heartbeat with one live apiserver `GET` per mesh region of the
account, sequential, against each region's own cluster, with no timeout of
its own (Req's 15 s and its transient retries applied) against a node
deadline of 5 s — and since `KURA_MESH_PEERS_SYNC` is rendered for every
mesh instance on this branch, the first successful `/peers` is what lifts a
managed pod's boot serving gate. One slow region cluster would have held
every pod of every account with a region there below that gate. The
reconciler already reads each `KuraInstance` every tick to project observed
state, so it now also records the parsed `status.peerRoles` on the
`kura_servers` row (`peer_roles`, `jsonb[]` of `{url, gateway}`; a failed
read keeps the last roles rather than blanking a live topology), and the
mesh view reads the rows. Staleness is one reconciler tick, and a server
with an open deployment keeps its last observed roles until the rollout
closes — the window in which a published role names a restarting pod no
node can see, so the local rule decides there regardless. The Kubernetes
client now forwards `:timeout` so no future caller can repeat the mistake.
The heartbeat carries no `peer_roles` at all: roles are keyed by each pod's
internal `KURA_NODE_URL`, a self-hosted node's peer list names a managed
region by one public URL, and `region_gateways` honours a role only for a
peer the node can see — the field could only be ignored while shipping
internal cluster addresses to customer infrastructure. Server tests cover
the reconciler recording and clearing roles, the Postgres-only read, and
both endpoints.

**D-28 — The controller demotes the same pods for the gateway as for the
primary, and resolves roles before the storage lifecycle.** Two INV-5
violations. Node evacuation dropped a pod on an annotated node from the
primary's health map but not from gateway eligibility, so the complement
rule named exactly that pod — Ready, not draining, no deletion timestamp —
pinned the public peer Service to it, and `evacuateMarkedNodes` deleted it
in the same pass; the client Service's `servedByAnotherPod` guard never
looked at the peer Service. The evacuating set is now listed once and shared
by both derivations, the gateway exclusion is unconditional (the gateway
falls back to the primary, so INV-3 holds; gating it would deadlock the
sequence, since the standby that has to move first is the pod the complement
rule names), and a pod is released only once the peer plane has moved too —
the peer Service no longer selects it and another pod is a ready endpoint
behind it, with no peer Service counting as released so non-mesh regions
never stall. Separately, the data-volume resize path returned before role
resolution, the pinned Services and the `peerRoles` status write, and keeps
returning until the rebuilt ordinal is serving — a cold bootstrap per
ordinal — so the peer Service stayed pinned to a deleted pod for a whole
rebuild (on `main` it selected every pod, so this was a regression). Role
resolution and the five pod-pinned Services now run above both storage
paths, and each early return republishes `peerRoles`; refusing to take down
the pinned pod instead cannot terminate, because the pin only moves once the
pod stops being routable, which the rebuild is what causes. Controller tests
cover evacuation × gateway, the resize following the surviving replica, and
the peer-plane release gate.

**D-29 — Forward responses capture the feed head and frontier together.** A
write could previously commit between the response's `head()` read and its
later `frontier_ms()` read. The scan excluded that write but the response could
advertise a frontier beyond its timestamp, letting the receiving gateway expose
newer records to another region before the omitted row arrived. Snapshot and
page responses now take both values while holding the feed's allocation lock.
Ring A: A-30.

**D-30 — Capacity declines are per entry on arrival-ordered passes.** The
descending legacy walk may stop considering segmented records once it reaches
one older than the next evictee because every following record is older. Feed
and ascending-region pages do not have that ordering guarantee. They now
decline only the individual record at listing and dispatch time, release its
claim for any waiter, and continue evaluating later entries. Their cursor or
watermark may still advance because the declined record was observed, but a
newer record later in the page is no longer skipped. Ring A: A-31.

**D-31 — Feed deactivation leaves a durable lifetime boundary.** Trimming to
the old head left a caught-up cursor equal to the floor valid after the feed
was reactivated. A write made while the feed was disabled could therefore be
missed without the reader taking a fresh snapshot. Deactivation now reserves
and discards one sequence and persists the floor through that gap. Every old
cursor is below the new floor, while the next lifetime starts strictly above
it and must bootstrap. Ring A: A-32.

**D-32 — Pull-to-push handover is level-triggered.** Membership updates carry
set differences, so a peer that stayed reachable while this node reverted its
flag, or while the peer stopped advertising pull, produced no discovery event.
The legacy scheduler had already removed it and therefore scheduled no catch-up
pass for the interval in which pull owned delivery. Each evaluation now compares
the reachable push peer set with the scheduler's present set. A newly eligible
peer is rediscovered even without a topology change, and its backward pass is
armed before the sync coordinator closes the pull link on that tick. Ring A:
A-33.
