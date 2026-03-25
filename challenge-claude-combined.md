# Combined Plan Review

Both reviews confirmed the plan's factual claims against the codebase at bookmark `push-rutomsmrzrks`. The direction is sound. Below are the combined challenges, deduplicated and organized by severity.

---

## Critical

### 1. Removing tombstones is unsafe unless replication also honors published cleanup barriers

*Source: GPT. Missed by Claude.*

This is the single biggest gap in the plan.

Today, the bootstrap path only materializes shared rows where `deleted_at IS NULL` (`key_value_replication_poller.ex:171`). The normal replication apply path (`apply_remote_batch`) is explicitly tombstone-aware — it splits rows into alive/deleted and processes deletions.

If per-entry tombstones are removed but old shared rows remain until background GC deletes them, then:

- a fresh node bootstrapping
- a restarted node
- a lagging node with an old watermark

will rematerialize rows that should already be considered dead. Those rows have no `deleted_at` (no tombstone was written), GC hasn't reached them yet, and the node has no other signal that they belong to a cleaned project.

The plan must also change:

- **bootstrap filtering** — skip rows belonging to projects with a `published_cleanup_cutoff_at >= row.source_updated_at`
- **normal replication polling** — same barrier check before materializing
- **shipper conflict resolution** — the upsert's `deleted_at` NULL-clearing logic in `upsert_shared_entries` needs to respect project-level barriers

Without this, the window between publication and GC completion is a correctness hole where stale data can reappear.

### 2. The failed-cleanup barrier is a data-loss-class bug, not a cleanliness issue

*Source: Claude. Missed by GPT.*

The plan frames the separation of active/published state as architectural improvement. In reality, the current code has a latent bug.

`expire_project_cleanup_lease` clears the lease but leaves `last_cleanup_at` untouched. The shipper permanently suppresses entries with `source_updated_at <= last_cleanup_at` even though the cleanup failed — S3 objects and shared KV rows were never deleted. If all 3 Oban attempts fail, the barrier stays permanently. Valid entries on the source node will never be replicated.

The plan's proposed split fixes this (only `published_cleanup_cutoff_at` acts as a barrier, and it's only set on success), but it should be framed as fixing a concrete bug.

---

## High

### 3. The sample replay poller is missing local side effects

*Source: GPT. Missed by Claude.*

Current local cleanup does more than delete local KV rows. It also clears:

- `Cachex` in-memory entries
- `KeyValueAccessTracker` lineage/state

The plan's `ProjectCleanupPoller` sketch uses `on_deleted_keys: fn _keys -> :ok end` — a no-op. A missed-node replay would leave stale in-memory cache entries and tracker state. The poller must reuse the same side-effect chain as the current `CleanProjectWorker` local invalidation helpers.

### 4. A single global watermark can be blocked by one bad project

*Source: GPT. Missed by Claude.*

The plan advances the watermark only after local apply succeeds. One project with a persistent local failure (disk permission issue, stat error, etc.) blocks replay for all later cleanup events behind it.

A better shape:

- a lightweight poller that discovers new published events
- a per-project Oban job for heavy local cleanup (disk + KV + metadata)
- local tracking of the last applied event per project

This avoids one broken project stalling global convergence.

### 5. Cutoff should be locked in the DB row, not threaded through user code

*Source: Claude. Missed by GPT.*

The fanout path uses `safe_cutoff` from `begin_project_cleanup` (threaded through local code). The published event stores `published_cleanup_cutoff_at` (the same value, passed to `publish_project_cleanup`). These should be identical — but the API allows passing a different value.

`publish_project_cleanup` should read the cutoff from `active_cleanup_cutoff_at` in the row rather than accepting it as a parameter. The schema already has the field. This eliminates a class of divergence bugs.

### 6. Cutoff semantics differ by store and must be preserved

*Source: GPT. Missed by Claude.*

The plan phrases cleanup as "everything at or before cutoff T is dead." But stores behave differently today:

- Shared KV tombstoning: `source_updated_at <= cutoff`
- Disk cleanup: **strictly before** the cutoff second (`DateTime.before?`)
- S3 cleanup: **strictly before** the cutoff second

Any redesign must preserve this distinction or risk same-second mismatches where a file is written at the exact cutoff second and gets incorrectly deleted or incorrectly retained depending on the store.

---

## Medium

### 7. The watermark cursor is more complex than necessary

*Source: Claude. Not in GPT.*

The 3-tuple watermark `(cleanup_published_at, account_handle, project_handle)` with a multi-clause tiebreaker works but is fragile. A `BIGSERIAL cleanup_event_id` column makes the watermark a single integer and the query `WHERE cleanup_event_id > $1 ORDER BY cleanup_event_id`. Timestamp collision edge cases disappear.

If the design also adopts per-project Oban jobs (challenge 4), the global watermark simplifies further — it only needs to discover events, not track per-project completion.

### 8. `published_cleanup_generation` serves no purpose as specified

*Source: Claude. Not in GPT.*

The plan proposes `published_cleanup_generation` as "a monotonic version per project" but never uses it in any query, watermark, or decision logic. If the watermark uses `cleanup_published_at` (or a sequence), the generation is redundant. Either use it concretely (e.g., per-project local "already applied" tracking) or drop it.

### 9. Missing index work

*Source: GPT. Missed by Claude.*

The plan adds polling by `cleanup_published_at` and background GC by project + cutoff, but does not mention indexes. Current shared entry indexes do not cover these access patterns. Expected additions:

- `projects(cleanup_published_at, account_handle, project_handle)` — for the poller
- `key_value_entries(account_handle, project_handle, source_updated_at)` — for the GC worker

Without these, the new paths risk becoming expensive.

### 10. The lease-token change adds unnecessary coupling

*Source: GPT. Not in Claude.*

Switching lease identity from timestamp to UUID token at the same time as introducing published cleanup state is a lot of moving parts. The important win is separating active coordination from published cleanup. The token change is optional and could be deferred.

If this is a single implementation with no rolling deploy concern, the coupling risk is lower — but it's still added complexity that doesn't contribute to the core correctness improvement.

---

## Low

### 11. GC SQL won't compile in PostgreSQL

*Source: both.*

PostgreSQL `DELETE` does not support `LIMIT` directly. Needs a subquery:

```sql
DELETE FROM key_value_entries
WHERE key IN (
  SELECT entry.key FROM key_value_entries entry
  JOIN projects project
    ON entry.account_handle = project.account_handle
   AND entry.project_handle = project.project_handle
  WHERE project.published_cleanup_cutoff_at IS NOT NULL
    AND entry.source_updated_at <= project.published_cleanup_cutoff_at
  LIMIT 1000
);
```

### 12. Post-publish crash causes redundant cleanup

*Source: Claude. Not in GPT.*

If the BEAM crashes after `publish_project_cleanup` commits but before Oban acks the job, Oban retries and starts a new full cleanup cycle. Safe but wasteful. `begin_project_cleanup` could check if a recent published cleanup already covers the time range and short-circuit.

### 13. CLI success vs cluster convergence remain different

*Source: GPT. Missed by Claude.*

The plan makes one accepted request enough for eventual cluster convergence. But the CLI still fans out to all endpoints and waits for all of them (`CleanService.swift:174`). A down endpoint still fails the user command even if the cluster will converge. The plan should state this explicitly — it's an accepted limitation, not an oversight.

### 14. The "O(1)" claim applies to shared writes only

*Source: GPT. Not in Claude.*

Publication becomes O(1) per project in the shared store. Total cleanup work is still proportional to local artifacts (disk scan, KV scan, metadata cleanup) and shared row count (GC). The plan should narrow the claim.

---

## Separate concern on the bookmark

*Source: GPT.*

`key_value_entries.ex:322` changed the replay-safety signature from `:crypto.hash(:sha256, payload)` to `:erlang.phash2(payload)`. `phash2` returns a small non-cryptographic hash — collisions are materially more likely. A collision could make a different batch look like an already-applied batch. This is unrelated to the plan but worth revisiting independently.

---

## Combined bottom line

The plan's diagnosis is accurate. The proposed architecture is the right direction. The single most important gap is **challenge 1**: tombstones cannot be removed without also teaching replication bootstrap, steady-state polling, and shipper upsert logic to honor project-level published cleanup barriers. Without that, the window between publication and GC completion is a correctness hole where stale data reappears on bootstrapping or lagging nodes.

The second most important gap is the **failed-cleanup barrier bug** (challenge 2), which the plan fixes but should frame as a concrete bug fix.

If this is a single implementation, the minimum bar is: publication + poller + barrier-aware replication + barrier-aware bootstrap + local side effects + GC + indexes, all landing together.
