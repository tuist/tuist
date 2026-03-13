# Review Round Four — Distributed KV Implementation

Only actual issues that need action. No commentary on things that work correctly.

---

## Bugs

### 1. Poller crashes on Postgres errors — no error handling

**File:** `cache/lib/cache/key_value_replication_poller.ex`

The poller has no `try/rescue` around `poll_once/0`. Any Postgres error (timeout, connection failure) propagates to `handle_info(:poll, ...)` and crashes the GenServer. The supervisor restarts it, but it immediately retries and crashes again. The shipper already has this pattern — the poller does not.

**Fix:** Add `try/rescue` around `poll_once/0` in `handle_info` with a warning log, matching the shipper.

### 2. Shipper crashes permanently on malformed KV key

**File:** `cache/lib/cache/key_value_replication_shipper.ex:104`

```elixir
:error -> raise "invalid KV key format for replication: #{entry.key}"
```

A single malformed row in `key_value_entries` causes a crash loop: the shipper restarts, fetches the same row (it still has `replication_enqueued_at`), and crashes again. Requires manual SQLite intervention to recover.

**Fix:** Log the error and clear `replication_enqueued_at` on the malformed row so it stops being retried.

### 3. `Disk.delete_project_before` uses local timezone for mtime comparison

**File:** `cache/lib/cache/disk.ex:120`

```elixir
with {:ok, %File.Stat{mtime: mtime}} <- File.stat(file_path),
```

`File.stat/1` defaults to `time: :local`. The `stat_mtime_to_datetime/1` helper then treats the local-timezone tuple as UTC. If the system timezone is not UTC, cutoff comparisons are wrong and files get incorrectly deleted or preserved.

**Fix:** Use `File.stat(file_path, time: :posix)` and convert the Unix timestamp directly via `DateTime.from_unix!/1`.

### 4. Remote fallback should not exist yet

**File:** `cache/lib/cache/key_value_store.ex:143-155`

The plan puts remote fallback in Phase 5 ("only if metrics justify"). It is implemented and gated behind a flag, but it has two problems if enabled:
- No explicit timeout on the Postgres query (inherits default 15s Ecto timeout — far too long for the request path).
- Missing `source_node` in `materialize_remote_hit` attrs.

**Fix:** Remove the remote fallback code entirely. Reintroduce it in Phase 5 if metrics justify it, with proper timeouts.

---

## Performance

### 5. Shipper queries cleanup cutoffs on every 200ms flush

**File:** `cache/lib/cache/key_value_replication_shipper.ex:88-91`

Every flush cycle hits `distributed_kv_project_cleanups` in Postgres for the batch's project scopes. That is 5 QPS per node, 35 QPS globally, almost always returning nothing.

**Fix:** Cache cutoffs in process state with a short TTL (5-10 seconds). Cleanup leases are 5 minutes, so staleness is negligible.

### 6. `tombstone_project_entries` re-tombstones already-tombstoned rows

**File:** `cache/lib/cache/distributed_kv/cleanup.ex:56-64`

The query does not filter `WHERE deleted_at IS NULL`. Already-tombstoned rows get their `updated_at` bumped, re-entering the poller stream unnecessarily.

**Fix:** Add `where: is_nil(entry.deleted_at)` to the query.

---

## Test Gaps

### 7. No end-to-end integration test for write-ship-poll

The shipper and poller tests mock everything. There is no test that writes locally, ships to Postgres, polls back, and verifies convergence. This is the single most important property of the system.

### 8. No test for cleanup-write races

The plan explicitly calls for these (line 551). The cleanup tests cover lease coalescing but not:
- A write with `source_updated_at > cleanup_started_at` surviving cleanup.
- A pre-cleanup write shipped after cleanup being discarded by the shipper stale check.
