# Review Round Two of `@-` Against `cache/plan.md`

This second pass re-checks the current `@-` implementation against `cache/plan.md`, but with a practical filter: focus on issues that are likely to matter in production, not rare edge cases where a node might miss a handful of rows once in a long while.

## Overall take

Most of the first-round issues now look fixed. The cleanup cutoff logic is atomic, cutoff-aware local cleanup keeps the final delete predicate, disk and S3 helpers now use `<=`, and remote miss fallback is no longer enabled by default.

I only see one remaining issue that still looks materially important in real-world operation.

## 1. Shared-store shipping is still not safely batched for hot existing keys

Severity: High

### What is wrong

`Cache.KeyValueReplicationShipper` now processes one flush in a single transaction, which is better than the earlier per-row transaction shape, but the steady-state behavior is still effectively row-by-row for existing keys:

- `cache/lib/cache/key_value_replication_shipper.ex:127`
- `cache/lib/cache/key_value_replication_shipper.ex:145`

The current flow is:

1. Load all existing shared rows for the batch.
2. Merge each pending local row in Elixir.
3. Run `insert_all` only for keys that do not already exist.
4. Run one `Repo.update!()` per existing key.

That still leaves two practical problems:

1. **Throughput stays worse than the plan assumes for the common case.** Once the system has warmed up, most shipped rows will already exist in Postgres. A flush of 1000 pending rows can still become roughly 1 select plus hundreds of individual `UPDATE` statements. That is not the amortized "small number of SQL transactions" shape the plan relies on for cross-region durability under sustained write load.
2. **Merge/apply is still not atomic per key.** Two nodes can read the same old shared row, both compute merges against that old value, and then whichever transaction writes last wins, even if the plan's LWW or tombstone rules say the other payload should survive.

This is especially relevant because the distributed design assumes the shared row is the global source of truth and that conflict resolution happens there, not approximately there.

### Why this conflicts with the plan/context

The plan is explicit that the shipper's viability depends on batching and on correct LWW behavior at the shared store:

- `cache/plan.md:91`
- `cache/plan.md:274`
- `cache/plan.md:288`
- `cache/plan.md:290`
- `cache/plan.md:292`
- `cache/plan.md:296`

The current implementation improves over round one, but it still falls short of the plan's core scaling assumption for the write path.

### Why this matters in practice

This is not a theoretical once-a-month bootstrap edge:

- Existing keys are the normal case after rollout, so the row-by-row update path is likely to dominate.
- Cross-region latency makes many individual statements materially more expensive than one real batch upsert.
- Concurrent writes to the same key are exactly the kind of thing this design needs to tolerate cleanly, because cache traffic fans out across nodes and regions.

Even if conflicting writes on the exact same key are not constant, this is still the one area where the current implementation most clearly risks both falling behind and choosing the wrong winner under contention.

### Suggested fix

Keep the merge logic in Elixir if that is the safest place for the business rules, but make the write side truly batch-oriented and conflict-safe:

1. Fetch the current shared rows for the batch once, as it does now.
2. Compute the merged target rows in Elixir.
3. Apply them with a real upsert path for all rows, not `insert_all` for new rows plus `update!` per existing row.
4. Encode the LWW and tombstone guardrails in the shared write itself, or otherwise ensure the write is conditional on the current shared row still matching the version that was merged from.
5. Keep compare-and-clear token handling as-is on the local side so newer pending state is not accidentally cleared.
6. Add one focused concurrency test where two shippers race on the same key and assert the final shared row matches the plan's LWW and tombstone rules.

## Prior review items

These first-round issues look addressed in the current code:

1. Cleanup coordination now uses one atomic upsert-and-return flow in `cache/lib/cache/distributed_kv/cleanup.ex`.
2. Local distributed cleanup now keeps the cutoff predicate in the actual delete path in `cache/lib/cache/key_value_entries.ex`.
3. Cutoff-aware disk and S3 deletion now use `<=` semantics in `cache/lib/cache/disk.ex` and `cache/lib/cache/s3.ex`.
4. Remote miss fallback is now opt-in and defaults to off in `cache/lib/cache/config.ex`, `cache/config/config.exs`, and `cache/config/runtime.exs`.

## Bottom line

If you want a short version: most of the design is now in much better shape, and I would not spend more time on rare poll/bootstrap corner cases right now. The one thing I would still push on before calling this aligned with the plan is the shipper's shared-write path.
