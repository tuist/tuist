# KV eviction follow-up plan

## Goal

Keep the size-aware KV eviction work, but remove avoidable request-path waiting, prevent maintenance queue starvation, and simplify failure handling without changing the public KV read contract.

## Principles

- SQLite busy is an internal cache-domain concern.
- Public KV reads should continue to expose only `{:ok, payload}` or `{:error, :not_found}` to the controller layer.
- Transient contention should be absorbed inside the cache domain.
- Unexpected database failures should not be misreported as cache misses.
- We cannot guarantee both zero blocking and always-successful reads under sustained SQLite lock contention; the implementation must choose one bounded contention strategy and document that trade-off clearly.

## 1. Restore the KV read contract at the store boundary

### Problem

- `cache/lib/cache/key_value_store.ex:59` currently allows `{:error, :busy}` from `get_key_value/4`.
- `cache/lib/cache_web/controllers/key_value_controller.ex:49` does not handle that case, so lock contention can raise a `CaseClauseError` and return a 500.

### Plan

- Keep `Cache.KeyValueStore.get_key_value/4` on a binary public contract: `{:ok, payload}` or `{:error, :not_found}`.
- Remove `{:error, :busy}` as a public return value from `cache/lib/cache/key_value_store.ex`.
- Keep the controller in `cache/lib/cache_web/controllers/key_value_controller.ex` unaware of SQLite contention details.
- Make contention handling fully internal to the store layer.
- Add tests in `cache/test/cache/key_value_store_test.exs` and `cache/test/cache_web/controllers/key_value_controller_test.exs` proving that the controller never sees `:busy` and successful read-through still returns the stored payload.

## 2. Use one contention strategy for request-path reads

### Problem

- `cache/lib/cache/key_value_store.ex:98` retries `Repo.get_by/2` up to 3 times with sleeps.
- SQLite is already configured with `busy_timeout: 30_000` in `cache/config/config.exs:10`.
- That stacks multiple waiting mechanisms without a single effective deadline and can make GET latency unpredictable.

### Plan

- Remove the current app-level retry loop in `cache/lib/cache/key_value_store.ex:98`.
- Recommended default: rely on SQLite's built-in busy handling as the only contention budget for the read-through query, and do not add extra sleeps or retry layers on top.
- If we decide later that one SQLite wait budget is still too large, lower the lower-level wait and then add a single app-level deadline; do not keep both at full strength.
- Match only known SQLite busy/locked failures in the contention path.
- Do not convert unrelated failures into `{:error, :not_found}`.
- Keep retry telemetry only if there is still a real retry loop worth measuring.

## 3. Narrow exception handling and keep unexpected failures observable

### Problem

- `cache/lib/cache/key_value_store.ex:118` rescues all exceptions and maps non-busy failures to `{:error, :not_found}`.
- `cache/lib/cache/key_value/prom_ex_plugin.ex:178` and `cache/lib/cache/key_value/prom_ex_plugin.ex:188` rescue everything and silently drop failures.

### Plan

- In `cache/lib/cache/key_value_store.ex`, special-case only known SQLite busy/locked failures.
- Let unexpected DB failures surface normally so they are logged and investigated instead of being misreported as misses.
- In `cache/lib/cache/key_value/prom_ex_plugin.ex`, replace broad rescues with explicit `Repo.query/1` result matching.
- Treat metrics polling as best-effort, but make failures observable with rate-limited logging or telemetry counters rather than silent drops.
- Return `:error` only for known query failures in the PromEx poller.

## 4. Put one real deadline around eviction DB work

### Problem

- `cache/lib/cache/key_value_eviction_worker.ex:106` calls `KeyValueEntries.delete_expired/2` repeatedly while walking retention days downward.
- Each call gets a fresh `max_duration_ms` budget from `cache/lib/cache/key_value_eviction_worker.ex:115`.
- The maintenance queue runs with concurrency 1 in `cache/config/config.exs:43`, so one long job can delay other maintenance work.

### Plan

- Track one worker-level deadline starting at `cache/lib/cache/key_value_eviction_worker.ex:25`.
- Apply that single budget to DB-facing eviction work: `fetch_size_state/0`, each eviction pass, and `run_size_maintenance_pass/0`.
- Pass remaining time into each internal eviction step instead of resetting the full budget per recursive call.
- If the deadline is exhausted, stop DB eviction work and emit telemetry/logging that makes the partial run explicit.
- Keep cleanup enqueueing for already-deleted hashes reliable even if the DB work budget is exhausted; do not strand CAS cleanup after a successful delete pass.
- Add tests in `cache/test/cache/key_value_eviction_worker_test.exs` and `cache/test/cache/key_value_eviction_integration_test.exs` proving the worker stops DB work once the total deadline is reached.

## 5. Simplify size-based eviction so each run does bounded incremental work

### Problem

- `cache/lib/cache/key_value_eviction_worker.ex:166` walks retention from 30 days toward 1 day.
- Each pass reruns `KeyValueEntries.delete_expired/2` over a new cutoff, which repeats scans and can greatly extend runtime.

### Plan

- Prefer one of these simpler strategies:
  - Preferred: perform a single oldest-first batched eviction loop until the DB drops below the release watermark or the worker deadline is reached.
  - Alternative: perform at most one retention-step reduction per Oban job, then reschedule another job if the DB is still oversized.
- For the preferred approach, keep a stable cursor and order across batches and re-check DB size after each batch so the loop has a clear stop condition.
- Prefer shorter lock windows and smaller bounded units of work over monolithic passes.
- Preserve the existing CAS cleanup grouping behavior while changing the eviction loop.

## 6. Revisit the batch query so the index can help without changing null semantics

### Problem

- `cache/lib/cache/key_value_entries.ex:130` orders by `coalesce(last_accessed_at, ...)` and `id`.
- The index in `cache/priv/repo/migrations/20260306120000_add_last_accessed_at_id_index_to_key_value_entries.exs:5` is on `[:last_accessed_at, :id]`.
- The `coalesce` expression may reduce or prevent effective use of that index.
- `NULL` `last_accessed_at` rows are currently valid eviction candidates, so any rewrite must preserve that behavior.

### Plan

- Verify whether null `last_accessed_at` rows are still expected long-term.
- If they are, choose an index-friendly query shape that preserves null handling, for example:
  - evict null-access rows in a dedicated path first, then use plain indexed ordering for non-null rows, or
  - backfill and migrate to a non-null field if that fits the product behavior better.
- Do not keep `coalesce(...)` in the hot path without checking the resulting SQLite query plan.
- Compare the before and after plans for the candidate query in `cache/lib/cache/key_value_entries.ex:126` before locking in the rewrite.

## 7. Remove the unused polling config instead of repurposing it

### Problem

- `cache/config/config.exs:77` and `cache/config/runtime.exs:139` define `key_value_eviction_poll_interval_ms`.
- There is no read site for that config.
- `Cache.KeyValue.PromExPlugin` has its own `poll_rate` for SQLite metrics polling, which is a separate concern from eviction scheduling.

### Plan

- Remove `key_value_eviction_poll_interval_ms` from `cache/config/config.exs` and `cache/config/runtime.exs` if it is not needed.
- Do not wire it into `cache/lib/cache/key_value/prom_ex_plugin.ex`; that would mix eviction cadence with metrics polling.
- If we want configurable SQLite metrics polling, introduce a new metrics-specific config name and wire it explicitly.

## 8. Keep the parts that already look good

These parts seem worth preserving while refactoring:

- The unique Oban worker setup in `cache/lib/cache/key_value_eviction_worker.ex:7` prevents overlapping eviction runs.
- The batch deletion approach in `cache/lib/cache/key_value_entries.ex:94` is directionally better than the old fixed-row cap.
- The extra telemetry and Grafana work in `cache/lib/cache/key_value/prom_ex_plugin.ex:72` and `cache/priv/grafana_dashboards/cache_service.json` is useful once the runtime behavior is tightened up.

## Suggested implementation order

1. Fix the controller/store `:busy` contract.
2. Remove app-level request retries and narrow read-path rescues.
3. Narrow PromEx error handling without introducing log spam.
4. Add a worker-level deadline for eviction DB work.
5. Simplify the size-based algorithm to avoid repeated rescans.
6. Revisit the batch query/index interaction while preserving null semantics.
7. Remove the unused polling config.
8. Update tests for the final behavior.

## Validation

- Run targeted KV store and controller tests covering transient contention in `cache/test/cache/key_value_store_test.exs` and `cache/test/cache_web/controllers/key_value_controller_test.exs`.
- Run eviction-focused tests in `cache/test/cache/key_value_eviction_worker_test.exs`, `cache/test/cache/key_value_eviction_integration_test.exs`, and `cache/test/cache/key_value_entries_test.exs`.
- Add a sanity check that the controller never receives a public `:busy` result.
- Add a sanity check that request-path waiting is governed by exactly one chosen contention strategy rather than nested retries and sleeps.
- Add a sanity check that unexpected DB failures are not translated into `:not_found`.
- Add a sanity check that a size-triggered eviction run stops DB work once the overall worker deadline is exhausted, while still preserving cleanup enqueueing for hashes already deleted.
- Compare SQLite query plans before and after the batch-query rewrite to confirm the new index can be used effectively.
