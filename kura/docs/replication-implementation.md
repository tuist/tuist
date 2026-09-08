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
