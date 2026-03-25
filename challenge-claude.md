# Plan Review: Challenges

## Verification of claims against actual code

All five factual claims in the plan were verified against the codebase at bookmark `push-rutomsmrzrks`:

1. **`last_cleanup_at` is overloaded** — Confirmed. `begin_project_cleanup/2` sets it as `clock_timestamp()` and returns it. `renew_project_cleanup_lease/3` uses it as a WHERE equality check (lease identity). `latest_project_cleanup_cutoffs/1` returns it to the shipper (barrier). It serves as lease identity, cutoff, barrier, and publication marker simultaneously.

2. **Tombstoning is O(keys)** — Confirmed. `tombstone_project_entries/3` does a single unbatched `UPDATE ... SET deleted_at` across all matching rows.

3. **Local disk cleanup depends on fanout** — Confirmed. The replication poller's `run_chunk_side_effects` only does `Cachex.del` and `KeyValueAccessTracker` operations. `Disk.delete` is never called from the poller. A node that missed fanout converges on KV metadata via tombstones but retains orphan disk files indefinitely.

4. **`cache_artifacts` metadata is never cleaned** — Confirmed. `CacheArtifact` rows are not deleted by `CleanProjectWorker` in either the winner or loser path.

5. **`Disk.delete_project_files_before` doesn't report deleted keys** — Confirmed. It accepts `on_progress:` but not `on_deleted_keys:` and returns `{:ok, count}`.

---

## Challenge 1: The plan undersells the failed-cleanup barrier bug

The plan says "if a cleanup fails and the lease expires, the active barrier disappears naturally" as if it is a cleanliness improvement. In reality, the current code has a latent data-loss-class bug here.

Today when cleanup fails, `expire_project_cleanup_lease` clears the lease but leaves `last_cleanup_at` untouched:

```elixir
def expire_project_cleanup_lease(account_handle, project_handle, cleanup_started_at) do
  _ =
    Repo.update_all(
      from(project in Project,
        where: project.last_cleanup_at == ^cleanup_started_at,
        update: [set: [
          cleanup_lease_expires_at: fragment("clock_timestamp()::timestamp"),
          # last_cleanup_at is NOT cleared
        ]]
      ), []
    )
  :ok
end
```

The shipper permanently suppresses entries with `source_updated_at <= last_cleanup_at` even though the cleanup failed and those entries were never cleaned from S3 or shared KV. If all 3 Oban attempts fail, the barrier stays permanently. Valid entries that exist on the source node and in S3 will never be replicated.

The plan's proposed split fixes this correctly — `published_cleanup_cutoff_at` is only set on successful publication, and `active_cleanup_cutoff_at` is cleared on failure — but should frame this as fixing a concrete bug, not just cleaner separation.

---

## Challenge 2: The watermark cursor is more complex than necessary

The plan proposes a 3-tuple watermark `(cleanup_published_at, account_handle, project_handle)` with a tiebreaker query:

```elixir
where: project.cleanup_published_at > ^watermark.published_at or
  (project.cleanup_published_at == ^watermark.published_at and
    (project.account_handle > ^watermark.account_handle or
      (project.account_handle == ^watermark.account_handle and
        project.project_handle > ^watermark.project_handle)))
```

This works but is fragile. Two projects publishing at the same microsecond is unlikely but not impossible under load. A simpler alternative: add a `BIGSERIAL cleanup_event_id` column to `projects` (or a separate table). The watermark becomes a single integer, the query becomes `WHERE cleanup_event_id > $1 ORDER BY cleanup_event_id`, and timestamp collision edge cases disappear entirely.

The trade-off is one more column, but the cursor logic becomes trivially correct.

---

## Challenge 3: `published_cleanup_generation` is dead weight as specified

The plan proposes `published_cleanup_generation` as "a monotonic version per project" but never uses it in any query, watermark, or decision logic. It only appears in the schema definition and the `RETURNING` clause of `publish_project_cleanup`.

If the watermark uses `cleanup_published_at` as the cursor, the generation is redundant. If the design switches to a global sequence (challenge 2), it is doubly redundant.

Either use it for something concrete (e.g., the local "already applied this generation" flag from challenge 6) or drop it.

---

## Challenge 4: The GC worker's SQL sketch won't compile

The plan shows:

```sql
DELETE FROM key_value_entries entry
USING projects project
WHERE entry.account_handle = project.account_handle
  AND entry.project_handle = project.project_handle
  AND project.published_cleanup_cutoff_at IS NOT NULL
  AND entry.source_updated_at <= project.published_cleanup_cutoff_at
LIMIT 1000;
```

PostgreSQL `DELETE` does not support `LIMIT` directly. This needs a subquery:

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

Minor, but the plan is otherwise precise with SQL/Ecto sketches so this should match.

---

## Challenge 5: Crash between publish and Oban ack causes redundant cleanup

If the winner finishes S3 deletion, calls `publish_project_cleanup` (which commits to PostgreSQL), and then the BEAM crashes before returning `:ok` to Oban:

- Oban retries the job
- `begin_project_cleanup` acquires a new lease (previous lease expired or was never cleared from the crashed process's perspective)
- A new cleanup cycle starts: full S3 re-scan, full disk re-scan, new publication

This is safe (idempotent) but wasteful. `begin_project_cleanup` could be made smarter: if a recent published cleanup already covers the requested time range (i.e., `published_cleanup_cutoff_at` is very recent), skip the new cleanup entirely or at least skip the S3 pass.

---

## Challenge 6: Fanout-then-poller double processing is underspecified

If a node receives the fanout and cleans locally, then the poller later sees the published event, it re-runs local cleanup. The plan says this is safe via idempotency.

But there is a sequencing question: the fanout path uses the `safe_cutoff` from `begin_project_cleanup` (passed through local code), while the published event stores `published_cleanup_cutoff_at` (the same value, passed to `publish_project_cleanup`). These should be identical — but the API allows passing a different value.

The cutoff should be locked in the active lease row at `begin_project_cleanup` time and retrieved at publication time, rather than threaded through user code where it could diverge. The proposed schema already has `active_cleanup_cutoff_at` — `publish_project_cleanup` should read it from the row rather than accepting it as a parameter.

Additionally: a node that cleaned via fanout will still process the published event from the poller (the watermark hasn't seen it yet). The disk walk will be fast (files already gone, `File.exists?` short-circuits), but the poller could skip disk cleanup entirely if a local flag in `Cache.DistributedKV.State` records that this project/generation was already applied locally.

---

## Summary

The plan's diagnosis of the current system is accurate on every point verified. The proposed architecture (publication + poller + GC) is sound.

The most important challenges are:

| # | Challenge | Severity |
|---|-----------|----------|
| 1 | Failed-cleanup barrier bug is undersold — it is data-loss-class | High (framing) |
| 2 | Watermark cursor is fragile — use a DB sequence | Medium (simplification) |
| 3 | `published_cleanup_generation` serves no purpose | Low (dead code) |
| 4 | GC SQL won't compile in PostgreSQL | Low (sketch error) |
| 5 | Post-publish crash causes redundant work | Low (optimization) |
| 6 | Cutoff should be locked in DB row, not threaded through code | Medium (correctness) |
