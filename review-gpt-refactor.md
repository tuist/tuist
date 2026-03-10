# Review

Reviewed the current `jj` bookmark `cschmatzler/fix-kv-explosion` with these rollout assumptions:

- KV metadata does not need backfill.
- S3 objects will be backfilled into the new CAS bucket with `rclone`.

Under those assumptions, I found two remaining issues.

## Findings

1. Medium - `cache/lib/cache/sqlite_maintenance_worker.ex:8`, `cache/config/config.exs:70`

   `SQLiteMaintenanceWorker` now runs `PRAGMA incremental_vacuum(128000)` against `Cache.KeyValueRepo` every 15 minutes, but it does so with the repo's normal `30_000` ms `busy_timeout` instead of the bounded busy-budget path used by `Cache.KeyValueEvictionWorker`. On a large KV DB, that maintenance pass can wait for or hold a write lock long enough for read-through GETs to burn their `2_000` ms contention budget and return misses during maintenance. That breaks the branch's core operational goal: maintenance must not interfere with client traffic. Reuse the same deadline-aware wrapper here, or keep KV vacuuming inside the eviction flow where the lock budget is already explicit.

2. Medium - `cache/lib/cache/key_value_eviction_worker.ex:54`, `cache/lib/cache/key_value_eviction_worker.ex:116`, `cache/lib/cache/key_value_eviction_worker.ex:208`

   Size-based eviction always deletes one batch before it runs any checkpoint/vacuum maintenance. If the DB is over the limit only because of reclaimable freelist or WAL bloat, the worker will eagerly delete retention-eligible KV rows and enqueue CAS cleanup even though a maintenance pass alone could have brought the database back under the release watermark. Run one maintenance pass before the first delete, then re-check size; after that, the existing delete/maintain/recheck loop looks good.
