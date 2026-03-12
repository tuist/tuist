# Review of `@-` Against `cache/plan.md`

This review checks the `@-` change (`feat(cache): distributed kv; initial llm impl`) against the intended design in `cache/plan.md`, the claimed execution in `cache/.plan`, and the implementation notes in `cache/learnings.md`.

## 1. Cleanup coordination is not canonical under concurrency

Severity: High

### What is wrong

`Cache.DistributedKV.Cleanup.begin_project_cleanup/2` currently does a read-then-insert/update flow inside a transaction:

- `cache/lib/cache/distributed_kv/cleanup.ex:15`
- `cache/lib/cache/distributed_kv/cleanup.ex:45`

That is still racy when multiple cache nodes receive the same `tuist cache clean --remote` fanout at the same time. Two nodes can observe no active cleanup, compute different `cleanup_started_at` values, and then race on insert/update. That breaks the plan's requirement that concurrent requests for the same project coalesce onto one canonical cutoff while the lease is active.

### Why this conflicts with the plan/context

The plan explicitly requires one shared coordination record and one canonical cleanup cutoff reused by concurrent requests:

- `cache/plan.md:203`
- `cache/plan.md:408`
- `cache/plan.md:410`
- `cache/plan.md:430`

This is also central to the learning that cleanup correctness depends on using one cutoff everywhere:

- `cache/learnings.md:5`

### Proposed fix

Make cleanup acquisition a single atomic shared-DB operation that always returns the persisted cutoff:

1. Use `INSERT ... ON CONFLICT ... DO UPDATE ... RETURNING cleanup_started_at, lease_expires_at` or an equivalent `Repo.insert`/`on_conflict` path.
2. Encode the lease reuse rule inside that statement:
   - if the existing lease is still active, keep the existing `cleanup_started_at`
   - if the lease expired, replace it with a fresh `cleanup_started_at`
3. Return the row selected by the database, not the local `now` value.
4. Add a concurrency test that starts two cleanup requests simultaneously and asserts they get the same cutoff while the lease is active.

## 2. Distributed local KV cleanup can delete post-cutoff writes

Severity: High

### What is wrong

`Cache.KeyValueEntries.delete_project_entries_before/3` first selects keys matching the cutoff and then performs a separate delete by `key in ^keys`:

- `cache/lib/cache/key_value_entries.ex:185`
- `cache/lib/cache/key_value_entries.ex:196`

`Cache.CleanProjectWorker` then invalidates all returned keys from Cachex:

- `cache/lib/cache/clean_project_worker.ex:64`

If a fresh write for one of those keys lands after the select but before the delete, the second query can still delete the new row because it no longer re-checks `source_updated_at` and `replication_enqueued_at`. That violates the required cleanup semantics that writes after `cleanup_started_at` must survive.

### Why this conflicts with the plan/context

The plan is explicit that distributed cleanup must preserve post-cutoff writes:

- `cache/plan.md:126`
- `cache/plan.md:131`
- `cache/plan.md:411`
- `cache/plan.md:415`
- `cache/plan.md:431`

The execution notes also claim this race was hardened:

- `cache/.plan:127`

### Proposed fix

Keep the cutoff predicate in the final delete, and only invalidate keys that were actually deleted:

1. Run the delete in a single transaction.
2. Use one `DELETE ... WHERE ... source_updated_at <= ^cutoff AND replication_enqueued_at IS NULL` query rather than a select-then-delete split.
3. If the caller needs deleted keys for Cachex invalidation, use `RETURNING key` when supported, or re-select within the same transaction from the exact delete target set.
4. Add a focused race test where cleanup and a post-cutoff write interleave, asserting the newer row and its Cachex value survive.

## 3. Cutoff-aware disk and S3 cleanup use `<` instead of `<=`

Severity: Medium

### What is wrong

Both distributed cleanup helpers truncate the cutoff to whole seconds and then only delete when timestamps are strictly before the cutoff:

- `cache/lib/cache/disk.ex:109`
- `cache/lib/cache/disk.ex:122`
- `cache/lib/cache/s3.ex:259`
- `cache/lib/cache/s3.ex:315`

That means files or objects whose current timestamp is exactly equal to `cleanup_started_at` are preserved, even though the plan requires deletion at or before the cutoff.

### Why this conflicts with the plan/context

The plan repeatedly specifies `<= cleanup_started_at` semantics for both local disk and S3 cleanup:

- `cache/plan.md:131`
- `cache/plan.md:132`
- `cache/plan.md:412`
- `cache/plan.md:413`
- `cache/plan.md:433`
- `cache/plan.md:434`

The execution notes say the implementation was tightened to be conservative with second-granularity timestamps:

- `cache/.plan:129`

Using strict `<` does the opposite at the equality boundary.

### Proposed fix

Implement explicit `<=` comparisons after normalization:

1. Replace `DateTime.before?/2` checks with `DateTime.compare(timestamp, safe_cutoff) in [:lt, :eq]`.
2. Keep the second-granularity normalization if needed for filesystem/S3 metadata, but make the equality behavior match the plan.
3. Add regression tests for exact-equality timestamps on both disk and S3 helpers.

## 4. The shipper is effectively per-row, not batched

Severity: Medium

### What is wrong

`Cache.KeyValueReplicationShipper.flush_pending_rows/0` loads pending rows as a batch but then processes them one by one:

- `cache/lib/cache/key_value_replication_shipper.ex:53`
- `cache/lib/cache/key_value_replication_shipper.ex:61`
- `cache/lib/cache/key_value_replication_shipper.ex:111`

Each row performs:

- scope parsing
- cleanup cutoff lookup
- a separate shared Postgres transaction
- a separate local token clear

That materially diverges from the design goal that burst traffic is absorbed by batching and coalescing, not by turning one flush into hundreds or thousands of remote transactions.

### Why this conflicts with the plan/context

The plan says the shipper should batch pending rows and amortize RTT across small numbers of SQL transactions:

- `cache/plan.md:91`
- `cache/plan.md:274`
- `cache/plan.md:292`
- `cache/plan.md:296`

The execution notes also claim Phase 2 implemented the shipper as part of that plan:

- `cache/.plan:64`
- `cache/.plan:71`

`cache/learnings.md:6` notes that merge logic moved into Elixir for safety, which is reasonable, but the current structure still does not preserve the plan's batching property.

### Proposed fix

Batch the remote work while keeping the merge logic in Elixir:

1. Group pending rows by project so cleanup cutoff lookup happens once per `(account_handle, project_handle)`.
2. Fetch all existing shared rows for the current batch in one query.
3. Merge rows in memory using the existing `Cache.DistributedKV.Logic` rules.
4. Apply inserts/updates in a small number of shared-DB transactions per batch instead of one transaction per row.
5. Clear local replication tokens only for successfully applied rows, preserving the existing compare-and-clear behavior.
6. Add a performance-oriented unit/integration test that verifies one flush of `N` rows does not issue `N` shared transactions.

## 5. Remote miss fallback is enabled by default, contrary to the plan

Severity: Medium

### What is wrong

`Cache.KeyValueStore` now falls back to the distributed repo on a local miss:

- `cache/lib/cache/key_value_store.ex:143`

and that behavior is enabled by default:

- `cache/lib/cache/config.ex:179`
- `cache/config/config.exs:108`

So in distributed mode, ordinary GET misses now put the shared Postgres repo on the request path unless explicitly disabled.

### Why this conflicts with the plan/context

The plan explicitly says the initial design keeps Postgres off the read path and treats remote miss fallback as an optional follow-up only if metrics justify it:

- `cache/plan.md:314`
- `cache/plan.md:556`

The distributed KV intent file repeats that shared-store operations must stay off the normal request hot path unless explicitly opted into:

- `cache/lib/cache/distributed_kv/AGENTS.md:9`

The execution notes also overstate alignment here by marking Phase 5 complete with remote miss fallback included:

- `cache/.plan:14`
- `cache/.plan:85`

### Proposed fix

Either remove the fallback from this change or make it opt-in and clearly separated from the base distributed rollout:

1. Change the default for `distributed_kv_remote_fallback_enabled` to `false`.
2. Gate the fallback behind an explicit env var and document it as an optional follow-up feature.
3. Keep the main distributed-mode tests exercising the planned local-only read path.
4. If fallback is kept, add telemetry around fallback hit rate and latency so the feature can be evaluated against the plan's stated rationale.

## Suggested next pass

The first fixes to land should be:

1. Make cleanup cutoff acquisition atomic.
2. Fix the local KV cleanup race so post-cutoff writes survive.
3. Correct the disk/S3 `<=` semantics.
4. Decide whether remote fallback belongs in this change at all.
5. Rework the shipper so its runtime behavior matches the scaling assumptions in `cache/plan.md`.
