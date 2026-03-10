# Code Review: `cschmatzler/fix-kv-explosion`

## Summary

This branch does three major things:

1. **Splits KV metadata into a dedicated SQLite database** (`KeyValueRepo`) to isolate it from artifact metadata and Oban jobs in the primary `Cache.Repo`
2. **Introduces a dedicated CAS S3 bucket** (`S3_CAS_BUCKET`) with migration-mode fallback reads from the shared bucket
3. **Overhauls KV eviction** with size-based eviction, deadline-bounded work, cursor-based batching, and SQLite contention handling

The change is large but well-structured. The cold-start migration approach (new DB starts empty, KV data repopulates from traffic) is pragmatic and avoids risky data migrations.

---

## Must Fix

### 1. Binary SQLite test files committed to the repository

**Files:** `cache/test_key_value.sqlite3`, `cache/test_key_value.sqlite3-shm`, `cache/test_key_value.sqlite3-wal`

The `.gitignore` has `test_key_value.sqlite*` but these files are tracked anyway -- they were likely staged before the gitignore entry was added. Remove them from tracking.

### 2. `changes.md` committed to the repo root

This is a planning/design document, not permanent documentation. Remove it before merge or move the content to the PR description.

---

## Should Investigate

### 3. `exists?/2` with `type: :cas` does not check the fallback bucket

`cache/lib/cache/s3.ex` -- `exists?/2` uses `bucket_for_type(type)` which resolves to the CAS bucket, but does not check the legacy shared bucket. If a CAS artifact only exists in the legacy bucket during migration, `exists?(key, type: :cas)` returns `false`. Verify no caller depends on this for correctness during migration.

### 4. `SQLiteMaintenanceWorker` does not vacuum `KeyValueRepo`

`cache/lib/cache/sqlite_maintenance_worker.ex` only runs `PRAGMA incremental_vacuum` against `Cache.Repo`. The new `KeyValueRepo` is only vacuumed during size-based eviction passes. On the common time-based eviction path, no periodic vacuum runs against `KeyValueRepo`.

With `auto_vacuum: :incremental`, freelist pages accumulate from deleted rows but are never reclaimed until a size-based eviction triggers or the DB crosses the size threshold. Consider adding `KeyValueRepo` to the maintenance worker, or document why this is acceptable.

### 5. Read-through latency ceiling is 30 seconds under contention

`cache/lib/cache/key_value_store.ex:96` -- `load_from_persistence` sets the `busy_timeout` to the configured default (30s). Under SQLite lock contention, a single KV GET request can block for up to 30 seconds before returning `{:error, :not_found}`. This is documented in `changes.md` as the chosen trade-off, but worth confirming this aligns with latency SLOs.

### 6. Eviction duration metric name vs unit mismatch

`cache/lib/cache/key_value/prom_ex_plugin.ex:88` -- The metric name is `[:cache, :kv, :eviction, :duration, :seconds]` but the measurement is `:duration_ms` with `unit: {:native, :millisecond}`. Verify the actual Prometheus output matches Grafana dashboard expectations.

---

## Code Quality

### 7. Duplicated utility functions across 4 modules

`busy_error?/1`, `set_busy_timeout!/1`, `remaining_time/1`, `file_size/1`, and `db_path/0` are duplicated across:

- `cache/lib/cache/key_value_entries.ex`
- `cache/lib/cache/key_value_eviction_worker.ex`
- `cache/lib/cache/key_value_store.ex`
- `cache/lib/cache/key_value/prom_ex_plugin.ex`

If the busy error detection needs to change (e.g., new SQLite error messages), all four places need updating. Consider extracting into a shared module like `Cache.SQLiteHelpers`.

### 8. `merge_grouped_hashes` in the eviction worker uses list concat + uniq + sort

`cache/lib/cache/key_value_eviction_worker.ex:319-325` -- Uses `++` followed by `Enum.uniq()` and `Enum.sort()`. Meanwhile, `KeyValueEntries.merge_grouped_hash_sets` uses `MapSet.union/2`. The worker converts MapSets to sorted lists (via `to_sorted_hash_lists`) before passing them to `merge_grouped_hashes`, which then re-deduplicates. The `Enum.uniq` is effectively a no-op since the lists are already unique from the MapSet conversion, but the approach is inconsistent and less efficient.

### 9. `with_repo_busy_timeout` in `key_value_store.ex` is a no-op for the timeout value

`cache/lib/cache/key_value_store.ex:118-128` -- Sets `busy_timeout` to the configured default (30s), runs the query, then restores to the same value (30s). The `checkout` for connection pinning is useful, but the PRAGMA manipulation adds overhead without changing behavior.

### 10. Redundant single-column index in new KV migration

`cache/priv/key_value_repo/migrations/20260309190000_create_key_value_entries.exs` -- Creates both `[:last_accessed_at]` and `[:last_accessed_at, :id]` indexes. The composite index already covers single-column lookups on `last_accessed_at` (leftmost prefix). The single-column index is redundant.

### 11. Unnecessary migration in the old repo

`cache/priv/repo/migrations/20260306120000_add_last_accessed_at_id_index_to_key_value_entries.exs` -- Adds a composite index to the old repo's `key_value_entries` table, which is no longer used after the migration to `KeyValueRepo`. Harmless but unnecessary -- runs on every deployment for tables that are effectively dead.

### 12. `emit_busy_and_finish` hardcodes `:size` trigger

`cache/lib/cache/key_value_eviction_worker.ex:63` -- When `fetch_size_state` returns `{:error, :busy}` at the very start, the trigger is hardcoded to `:size`. The busy happened during the initial size check, before the trigger type was actually determined. Minor telemetry inaccuracy.

### 13. Grafana dashboard threshold cosmetic mismatch

`cache/priv/grafana_dashboards/cache_service.json:1932` -- The yellow threshold is `24676863283` (~22.98 GiB). The actual hysteresis release target in config is `24696061952` (23 GiB exactly). The difference is ~19 MiB. Not functionally important but the dashboard should match the config default.

---

## S3 Bucket Splitting Observations

### Presign fallback adds latency

`cache/lib/cache/s3.ex:65-72` -- When CAS fallback is active, every presign request does a synchronous HEAD request to the primary CAS bucket before generating the URL. `download/2` also does HEAD-then-download, so a CAS download with fallback can do up to 4 S3 round-trips. Acceptable as a temporary migration cost but worth documenting the expected removal timeline.

### `delete_all_with_prefix` does not clean the fallback bucket

`cache/lib/cache/s3.ex:289` -- When deleting CAS artifacts for a project, only the primary CAS bucket is cleaned. Pre-migration artifacts in the shared bucket are not deleted. This is probably intentional (the shared bucket still serves other artifact types with the same prefix), but CAS artifacts in the legacy bucket will linger until the bucket is decommissioned.

### Backfill upload on fallback hit is correct

`cache/lib/cache/s3_transfer_worker.ex:97-108` -- On fallback hit, a backfill upload is enqueued to copy the artifact to the primary CAS bucket. This is the right migration behavior.

### Double deletion when buckets are the same

`cache/lib/cache/clean_project_worker.ex` -- When `S3_CAS_BUCKET` equals `S3_BUCKET` (no migration), the same prefix is deleted from the same bucket twice. Harmless but wasteful. Not worth fixing given it's a temporary state.

---

## Eviction Logic Observations

### Cursor-based batching is well-designed

The split of null vs non-null candidate queries (`cache/lib/cache/key_value_entries.ex:200-265`) allows the `(last_accessed_at, id)` composite index to be used effectively for the non-null path. Null entries are evicted first, which is correct -- they represent entries that were never accessed.

### Transaction wrapping in `delete_chunk` prevents TOCTOU

`cache/lib/cache/key_value_entries.ex:302-328` -- Wrapping verify+delete in a transaction prevents races where an entry could be accessed between the verification query and the delete. The `{:ok, _}` pattern match on the transaction result will raise a `MatchError` on failure, which is caught by the `rescue` in the calling code -- safe in practice but implicit.

### Size-based eviction loop is well-bounded

The deadline pattern, hysteresis gap (25 GiB trigger, 23 GiB release), and batch-then-vacuum-then-recheck cycle are robust. The `unique` Oban constraint prevents overlapping runs.

### Cron frequency change from 6h to 15min

`cache/config/config.exs:67` -- Combined with the `unique` constraint, the worker runs at most every 15 minutes but won't overlap. Reasonable for size-based eviction that needs faster reaction times.

---

## Test Coverage

Test coverage is thorough:

- `key_value_entries_test.exs`: Updated for 3-tuple returns, new tests for batched eviction, deadline handling, null-first ordering
- `key_value_eviction_worker_test.exs`: Size-based eviction, floor-limited status, busy contention, deadline expiration, partial work preservation
- `key_value_eviction_integration_test.exs`: Full eviction cycle, cascading hash cleanup, maintenance-only shrink, lock contention safety
- `key_value_store_test.exs`: Contention-as-miss behavior, non-busy error propagation
- `s3_test.exs`: CAS bucket presign, fallback, exists, download, delete
- `s3_transfer_worker_test.exs`: Fallback hit backfill upload
- `clean_project_worker_test.exs`: Dual-bucket deletion
- `cas_controller_test.exs`: `type: :cas` option passing
- `key_value_controller_test.exs`: Contention-as-miss from controller level

One fragility note: several size-based eviction tests stub only specific PRAGMAs and rely on deadline exhaustion (`max_duration_ms: 0`) to prevent reaching unstubbed PRAGMAs like `wal_checkpoint` and `incremental_vacuum`. A change in execution order could cause unexpected test failures.

---

## Migration Safety

The single-repo to dual-repo migration is handled safely:

- **Cold start:** New `KeyValueRepo` starts empty. KV data repopulates from traffic. No data migration needed.
- **Both repos in `ecto_repos`:** Migrations run for both on startup.
- **Old tables left in place:** No drop migration. Can be cleaned up later.
- **No compile-time enforcement:** Nothing prevents accidentally using `Repo` with KV schemas. All call sites have been correctly updated, but this relies on developer discipline.
