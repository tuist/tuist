# Distributed project cleanup redesign plan

## Constraints

**Do not change the CLI contract.**

That means:

- keep the current CLI-facing clean flow and request shape intact
- keep the current cache clean API shape intact unless there is a very strong reason not to
- do **not** make correctness depend on a CLI change

The CLI may keep fanning out cleanup requests to every cache endpoint exactly as it does today. This redesign changes the cache-side correctness model, not the CLI contract.

## Additional constraint for this document

This plan is for **one complete implementation**, not a phased rollout plan.

That means the implementation must land all required correctness properties together. In particular, it is **not** enough to add a published cleanup event unless the same implementation also makes replication and replay honor that event correctly.

---

## Executive summary

I would still challenge the current design in one specific way:

> a project-wide cleanup should not be represented primarily as a batch of per-key tombstones, and local cleanup should not depend on fanout reaching every node.

However, the redesign has to be more precise than the original draft:

- keep the existing CLI fanout unchanged as a fast path
- make a **published project cleanup** the durable source of truth
- make every node eventually apply that published cleanup locally, even if it missed fanout
- keep stale rows from being reintroduced **before** background GC deletes old shared rows
- fix the existing failed-cleanup barrier bug by separating **active** cleanup state from **published** cleanup state
- make local cleanup exact by removing matching `cache_artifacts` metadata for files that were actually deleted

In short:

> retain fanout for speed, but make correctness come from published cleanup state + barrier-aware replication + local replay.

---

## What is wrong with the current design

## 1. `projects.last_cleanup_at` is overloaded

Today the same field is acting as:

- active cleanup identity
- active cleanup cutoff
- shipper barrier
- latest known cleanup marker

That is difficult to reason about and it causes a real bug.

## 2. Failed cleanups can leave a permanent barrier behind

Today when cleanup fails, the cleanup lease is expired, but `last_cleanup_at` remains set.

That means the shipper can keep suppressing rows at or before that cutoff even though cleanup never published a successful outcome and shared state was never fully deleted.

This is not just an architectural cleanliness issue. It is a correctness bug:

> a failed cleanup can permanently suppress valid rows from being replicated.

Any redesign must fix this by separating:

- **active cleanup state** — only valid while the lease is alive
- **published cleanup state** — only set after successful shared cleanup publication

## 3. Local disk cleanup still depends on direct fanout

Today:

- reached nodes clean local KV + local disk immediately
- the winner deletes shared S3 and tombstones shared KV rows
- missed nodes eventually converge local KV metadata via replication tombstones
- missed nodes do **not** have a shared-state-driven mechanism that later cleans local disk

That means one missed node can keep orphan disk files indefinitely.

## 4. Per-entry tombstoning is the wrong primary abstraction

A project cleanup is one semantic fact:

- everything for `account/project` at or before cleanup cutoff `T` is dead

Representing that primarily as one shared `UPDATE ... SET deleted_at = cutoff` per row is:

- expensive at cleanup time
- the wrong level of abstraction
- unnecessary if publication + replay + GC exist

## 5. Removing tombstones is unsafe unless replication becomes barrier-aware

This is the biggest gap in the original draft.

Today shared replication is tombstone-aware:

- bootstrap materializes only rows with `deleted_at IS NULL`
- steady-state apply treats rows with `deleted_at` as deletions

If the system stops writing per-entry tombstones but leaves old shared rows in place until background GC physically deletes them, then:

- a fresh node
- a restarted node
- a lagging node with an old watermark

can rematerialize rows that are already semantically dead.

So the redesign must ensure that the same implementation also makes:

- bootstrap
- steady-state polling
- shipper stale-row suppression
- any shared upsert/resurrection path

honor published project cleanup barriers.

## 6. Project cleanup currently leaves local `cache_artifacts` metadata stale

`CleanProjectWorker` deletes files from disk, but it does not precisely delete matching local `cache_artifacts` rows.

That means project cleanup can leave the node locally inconsistent:

- file is gone
- metadata still claims it exists

The redesign should fix this as part of the same implementation.

---

## Design goals

1. **No CLI contract change**
2. **One accepted cleanup request must be enough for eventual cluster convergence**
3. **CLI command success semantics remain unchanged**
   - the CLI still fans out and may still fail if some endpoint is down
   - this redesign changes correctness, not user-facing success aggregation
4. **Fix the failed-cleanup barrier bug**
5. **Any node that misses fanout must still converge later**
6. **Published cleanup must prevent stale rows from being rematerialized before GC**
7. **Shared S3 cleanup remains single-winner**
8. **Local cleanup remains idempotent**
9. **Local cleanup must include exact `cache_artifacts` metadata cleanup**
10. **Heavy local replay work must not let one broken project block all later events**
11. **Shared KV compaction happens asynchronously**
12. **The implementation should minimize mixed-version rollout risk**

---

## Proposed design

## 1. Keep the current CLI contract and fanout, but make fanout a fast path only

Do **not** change the CLI request contract.

The CLI can keep fanning out exactly as it does today.

That fanout remains useful because:

- reachable nodes clean quickly
- hot nodes invalidate local cache quickly
- shared S3 cleanup can start quickly on the winner

But correctness must no longer depend on every node receiving the request directly.

The new correctness story should be:

> if at least one node accepts the cleanup and successfully publishes it, every node will eventually apply that cleanup locally.

---

## 2. Split active cleanup state from published cleanup state

The current `last_cleanup_at` field should be replaced by explicit active and published cleanup fields.

### Proposed shared schema shape

I would evolve `cache/lib/cache/distributed_kv/project.ex` and the shared migration history toward something like:

```elixir
schema "projects" do
  field :account_handle, :string, primary_key: true
  field :project_handle, :string, primary_key: true

  field :active_cleanup_cutoff_at, :utc_datetime_usec
  field :cleanup_lease_expires_at, :utc_datetime_usec

  field :published_cleanup_generation, :integer
  field :published_cleanup_cutoff_at, :utc_datetime_usec
  field :cleanup_published_at, :utc_datetime_usec
  field :cleanup_event_id, :integer

  field :updated_at, :utc_datetime_usec
end
```

### Why this is better

- `active_cleanup_cutoff_at` is only for in-progress cleanup coordination
- `published_cleanup_*` is only for completed cleanup state
- `published_cleanup_generation` becomes a real per-project idempotency version
- `cleanup_event_id` gives the replay discovery path a simple global cursor
- failed cleanups can clear active state without leaving a permanent published barrier behind

### Important note about lease identity

For this implementation, I would **not** introduce a new UUID lease token.

The important change is the split between active and published state. Changing lease identity semantics at the same time adds complexity without improving the core correctness model.

Keeping cutoff-based active lease identity for now reduces rollout risk while still fixing the real bug.

---

## 3. The shared DB row must own the cleanup cutoff

The cleanup cutoff should be established once in shared state and then reused from shared state.

That means:

- `begin_project_cleanup/2` creates or refreshes the active cleanup row using shared DB time
- `active_cleanup_cutoff_at` is the source of truth for this cleanup run
- `publish_project_cleanup/2` should publish the cutoff stored in the row
- caller code should **not** pass an arbitrary cutoff back into publication

### Suggested API shape in `Cache.DistributedKV.Cleanup`

```elixir
def begin_project_cleanup(account_handle, project_handle) do
  # Creates or acquires the active cleanup lease.
  # Stores active_cleanup_cutoff_at = clock_timestamp().
  # Returns {:ok, active_cleanup_cutoff_at}.
end


def renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at) do
  # Extends the lease only if the same active cutoff is still current and the lease is alive.
end


def publish_project_cleanup(account_handle, project_handle, active_cleanup_cutoff_at) do
  # Atomically:
  # - verifies the same active cleanup is still current
  # - reads active_cleanup_cutoff_at from the row
  # - increments published_cleanup_generation
  # - sets published_cleanup_cutoff_at = active_cleanup_cutoff_at
  # - sets cleanup_published_at = clock_timestamp()
  # - sets cleanup_event_id = nextval(...)
  # - clears active_cleanup_cutoff_at / cleanup_lease_expires_at
end


def expire_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at) do
  # Clears only active cleanup state for that same active cleanup.
  # Does not leave a published barrier behind.
end
```

### Why this matters

This guarantees that:

- the published cutoff is exactly the cutoff the shared store accepted
- publication cannot accidentally diverge from the active cleanup row
- fanout + replay use the same logical cleanup boundary

---

## 4. Use published cleanup barriers everywhere before removing tombstones

This is the non-negotiable part of the redesign.

If per-entry tombstones stop being written on the cleanup path, the same implementation must also ensure that shared rows behind a published cleanup barrier cannot be rematerialized while they still exist in shared storage.

## 4a. Shipper barrier semantics

The shipper should suppress stale local pending rows using an **effective barrier** per project:

- if an active cleanup exists and its lease is still alive, use `active_cleanup_cutoff_at`
- otherwise, if a published cleanup exists, use `published_cleanup_cutoff_at`
- otherwise, no barrier exists

This preserves the current stale-write suppression behavior while fixing the failed-cleanup case:

- active barrier disappears naturally if cleanup fails and the lease is cleared/expired
- published barrier persists only after successful publication

## 4b. Bootstrap must honor published cleanup barriers

Bootstrap cannot just materialize all shared rows with `deleted_at IS NULL` anymore.

It must skip rows where:

- the project has a published cleanup cutoff, and
- `row.source_updated_at <= published_cleanup_cutoff_at`

That prevents a fresh or restarted node from rematerializing already-cleaned rows before GC physically deletes them.

## 4c. Steady-state poller must honor published cleanup barriers

The same barrier rule must be applied in steady-state replication polling.

A node that is behind the shared watermark must not materialize rows that are semantically dead just because background GC has not removed them yet.

## 4d. Shared upsert/resurrection paths must not reintroduce rows behind the published barrier

The shared write path must never resurrect a row at or below a published cleanup barrier.

The primary protection is shipper-side stale-row suppression, but the design should treat this as a shared invariant:

> rows at or below a published cleanup cutoff must not re-enter the distributed state.

At minimum, all shipper paths that prepare shared writes must filter rows against the published barrier before insert/update.

---

## 5. Publish one project cleanup event and discover it globally

When the winner finishes the shared part of cleanup successfully, it should publish exactly one project cleanup event by updating the project row.

That publication should:

- increment `published_cleanup_generation`
- set `published_cleanup_cutoff_at`
- set `cleanup_published_at`
- assign a new monotonic `cleanup_event_id`
- clear active cleanup state

### Why keep both generation and event id

- `cleanup_event_id` is a global discovery cursor for the node-local replay discovery poller
- `published_cleanup_generation` is a per-project idempotency version for local apply

That makes both fields useful.

---

## 6. Use a lightweight discovery poller plus per-project local apply jobs

The original draft used one poller that directly performed all local cleanup work. I would change that.

A single global poller should **discover** published cleanup events, but it should **not** do heavy disk cleanup inline.

### New components

- `Cache.ProjectCleanupDiscoveryPoller`
- `Cache.ApplyProjectCleanupWorker`

### Discovery poller responsibility

The discovery poller should:

- scan shared `projects` rows ordered by `cleanup_event_id`
- persist a local discovery watermark in `Cache.DistributedKV.State`
- enqueue one unique local apply job per `(account_handle, project_handle, published_cleanup_generation)`
- advance its discovery watermark only after enqueueing those jobs successfully

### Why this is better than one heavy poller

It avoids one bad project blocking all later events.

If one project has:

- a disk traversal failure
- a permission issue
- some other local cleanup error

that failure stays isolated to that project’s retrying job rather than stopping global replay discovery.

### Local idempotency

Each node should also persist the last applied generation per project in local state.

That gives the apply worker a clear rule:

- if local applied generation is already `>= published_cleanup_generation`, return `:ok`
- otherwise apply local cleanup and then persist the new applied generation

This makes `published_cleanup_generation` a real part of the design rather than dead weight.

---

## 7. Local replay must use the same cleanup semantics as direct fanout

The local apply worker must **not** be a simplified delete-only path.

It should reuse the same local cleanup semantics as the current direct cleanup worker, including:

- local KV deletion
- `Cachex` invalidation
- `KeyValueAccessTracker` cleanup
- local disk deletion
- exact `cache_artifacts` metadata cleanup

That ensures that a node that only learns through the published cleanup event ends up in the same local state as a node that received the original fanout request directly.

---

## 8. Make local `cache_artifacts` cleanup exact

This should be fixed as part of the same implementation.

### Problem

`Disk.delete_project_files_before/4` currently supports `on_progress:` but not `on_deleted_keys:` and returns only `{:ok, count}`.

That means `CleanProjectWorker` cannot precisely delete matching `cache_artifacts` rows.

### Proposed `Disk` API

```elixir
def delete_project_files_before(account_handle, project_handle, cutoff, opts \\ []) do
  # opts:
  #   on_progress: fn -> :ok end
  #   on_deleted_keys: fn keys -> :ok end
end
```

### Suggested usage

```elixir
Disk.delete_project_files_before(account_handle, project_handle, cutoff,
  on_progress: on_progress,
  on_deleted_keys: fn keys -> CacheArtifacts.delete_by_keys(keys) end
)
```

### Why this matters

After cleanup, the node should not retain metadata for files that no longer exist.

That is part of the correctness bar for project cleanup.

---

## 9. Keep disk and S3 cutoff semantics explicit

The redesign should preserve the current store-specific cutoff behavior.

Today:

- shared KV cleanup is conceptually `<= cutoff`
- disk cleanup is **strictly before** the cutoff second
- S3 cleanup is **strictly before** the cutoff second

That distinction exists for real reasons and should stay explicit in the design.

So the semantic wording in this plan should be read as:

> everything at or before the logical cleanup cutoff is dead, but store-specific physical deletion keeps the current second-truncation and strict-before behavior where required for safety.

---

## 10. `CleanProjectWorker` should keep its fast path, but publication replaces tombstoning

### Winner path

The winner should:

1. acquire active cleanup state with shared DB time
2. perform local cleanup fast path on this node
3. delete shared S3 artifacts as today
4. publish the completed cleanup event
5. **not** write per-entry tombstones on the main cleanup path

### Duplicate path

If another node receives the same cleanup while one cleanup is already active, it should:

- read the active cleanup cutoff
- perform node-local cleanup immediately with that cutoff
- not delete shared S3
- not publish a cleanup event

### Why keep direct local cleanup at all

Because fanout is still useful as a latency optimization.

The difference after this redesign is that:

- direct fanout is a speed optimization
- published cleanup + local replay is the correctness mechanism

---

## 11. Background shared GC replaces tombstone-heavy cleanup work

Once published cleanup barriers are understood everywhere, the system no longer needs per-entry tombstones as the primary cleanup mechanism.

Instead:

- publish the project cleanup once
- let nodes honor the barrier immediately
- let local apply jobs clean node-local state
- let background GC physically delete old shared rows later in bounded batches

### New worker

- `Cache.DistributedKVGCWorker`

### PostgreSQL-compatible batched delete shape

The GC worker should use a real PostgreSQL-compatible batched delete, for example:

```sql
WITH doomed AS (
  SELECT entry.key
  FROM key_value_entries entry
  JOIN projects project
    ON entry.account_handle = project.account_handle
   AND entry.project_handle = project.project_handle
  WHERE project.published_cleanup_cutoff_at IS NOT NULL
    AND entry.source_updated_at <= project.published_cleanup_cutoff_at
  ORDER BY entry.account_handle, entry.project_handle, entry.source_updated_at, entry.key
  LIMIT 1000
)
DELETE FROM key_value_entries entry
USING doomed
WHERE entry.key = doomed.key;
```

### GC safety rule

The worker must only delete shared rows where:

- the project has a published cleanup cutoff
- the row is at or below that cutoff

That keeps publication cheap while allowing compaction to happen slowly and safely in the background.

---

## 12. Required indexes and local state

The design needs explicit support for its new access patterns.

### Shared indexes

At minimum, I would expect indexes along these lines:

- `projects(cleanup_event_id)` or a partial equivalent for published rows
- `projects(cleanup_published_at, account_handle, project_handle)` if publication time remains part of the query path
- `key_value_entries(account_handle, project_handle, source_updated_at, key)` for project-scoped GC and barrier checks

The exact final index set can be tuned, but the redesign is incomplete without indexing work.

### Local state keys

The node-local state should include at least:

- a global cleanup discovery watermark keyed by latest `cleanup_event_id`
- per-project last applied generation

---

## 13. Single-implementation completeness bar

Because this is one implementation rather than a phased rollout, the design is only complete if all of the following land together:

1. **Split active cleanup state from published cleanup state**
2. **Fix failed-cleanup barrier behavior**
3. **Make shipper barrier logic use active/published semantics correctly**
4. **Make bootstrap honor published barriers**
5. **Make steady-state polling honor published barriers**
6. **Prevent shared writes from reintroducing rows behind published barriers**
7. **Replace heavy replay-in-poller logic with discovery poller + per-project apply jobs**
8. **Make local replay use full local cleanup side effects**
9. **Make `cache_artifacts` cleanup exact**
10. **Replace cleanup-path tombstoning with background GC**
11. **Add required indexes and local state**

If any of those are missing, the redesign is not complete enough to remove tombstones safely.

---

## Concrete code changes I would make

## Cache service

### 1. Refactor distributed cleanup state

Files:

- `cache/lib/cache/distributed_kv/project.ex`
- `cache/lib/cache/distributed_kv/cleanup.ex`
- new migration under `cache/priv/distributed_kv_repo/migrations/`

Changes:

- replace `last_cleanup_at` with explicit active/published cleanup fields
- add `cleanup_event_id`
- keep active cutoff as the lease identity for now
- clear active state on failed cleanup instead of leaving a permanent barrier behind

### 2. Add cleanup discovery poller and local apply worker

Files:

- `cache/lib/cache/project_cleanup_discovery_poller.ex`
- `cache/lib/cache/apply_project_cleanup_worker.ex`
- `cache/lib/cache/application.ex`

Changes:

- discovery poller reads published cleanup events by `cleanup_event_id`
- discovery poller enqueues one unique local apply job per project generation
- local apply worker performs node-local cleanup idempotently
- local state records discovery watermark and last applied generation

### 3. Change `CleanProjectWorker`

File:

- `cache/lib/cache/clean_project_worker.ex`

Changes:

- keep immediate local cleanup fast path for directly reached nodes
- winner still deletes shared S3
- winner publishes project cleanup instead of tombstoning shared KV rows
- duplicate requests still perform local cleanup using active cleanup cutoff

### 4. Change shipper barrier lookup semantics

File:

- `cache/lib/cache/key_value_replication_shipper.ex`

Changes:

- replace `latest_project_cleanup_cutoffs/1` with explicit active/published barrier lookup semantics
- suppress stale pending rows against the effective barrier
- ensure rows at or below published barrier cannot be reintroduced to shared state

### 5. Change bootstrap and steady-state polling to honor published barriers

Files:

- `cache/lib/cache/key_value_replication_poller.ex`
- possibly supporting helpers in `cache/lib/cache/distributed_kv/cleanup.ex`

Changes:

- bootstrap skips rows behind published project cleanup barriers
- steady-state polling skips rows behind published barriers
- no node may rematerialize stale rows between publication and GC

### 6. Fix exact local artifact metadata cleanup

Files:

- `cache/lib/cache/disk.ex`
- `cache/lib/cache/cache_artifacts.ex`
- `cache/lib/cache/clean_project_worker.ex`
- `cache/lib/cache/apply_project_cleanup_worker.ex`

Changes:

- add `on_deleted_keys` callback support to disk cleanup
- delete `cache_artifacts` rows only for actually deleted local files

### 7. Add shared KV GC worker

Files:

- `cache/lib/cache/distributed_kv_gc_worker.ex`
- `cache/lib/cache/application.ex`
- remove or repurpose `cache/lib/cache/tombstone_purge_worker.ex`

Changes:

- periodically batch-delete shared rows older than the published project cleanup cutoff
- keep work bounded by page size and time budget

---

## Example rewritten `CleanProjectWorker` flow

This is the shape I would target.

```elixir
defp perform_distributed_cleanup(account_handle, project_handle, attempt) do
  case Cleanup.begin_project_cleanup(account_handle, project_handle) do
    {:ok, active_cleanup_cutoff_at} ->
      perform_primary_distributed_cleanup(account_handle, project_handle, active_cleanup_cutoff_at)

    {:error, :cleanup_already_in_progress} ->
      perform_duplicate_distributed_cleanup(account_handle, project_handle, attempt)
  end
end


defp perform_primary_distributed_cleanup(account_handle, project_handle, active_cleanup_cutoff_at) do
  safe_cutoff = DateTime.truncate(active_cleanup_cutoff_at, :second)
  on_progress = fn -> Cleanup.renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at) end

  with :ok <- perform_local_node_cleanup(account_handle, project_handle, safe_cutoff, on_progress),
       :ok <- maybe_delete_xcode_s3_artifacts(account_handle, project_handle, safe_cutoff, on_progress),
       :ok <- delete_s3_artifacts_with_cutoff(account_handle, project_handle, :cache, "cache", safe_cutoff, on_progress),
       {:ok, _published} <- Cleanup.publish_project_cleanup(account_handle, project_handle, active_cleanup_cutoff_at) do
    :ok
  else
    {:error, reason} = error ->
      :ok = Cleanup.expire_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at)
      error
  end
end
```

The big change is the last line:

- publish one cleanup event
- do not write per-entry tombstones here

---

## Example discovery poller flow

```elixir
def handle_info(:poll, state) do
  {events, next_watermark} = Cleanup.list_published_cleanups_after_event_id(state.watermark, @page_size)

  Enum.each(events, fn event ->
    :ok = enqueue_apply_project_cleanup(event)
  end)

  if events != [] do
    :ok = Cleanup.put_local_project_cleanup_watermark(next_watermark)
  end

  schedule_poll()
  {:noreply, %{state | watermark: next_watermark}}
end
```

The important property is that this poller does **discovery only**, not heavy local cleanup.

---

## Example local apply worker flow

```elixir
def perform(%Oban.Job{args: %{
      "account_handle" => account_handle,
      "project_handle" => project_handle,
      "generation" => generation,
      "cutoff" => cutoff
    }}) do
  with false <- already_applied?(account_handle, project_handle, generation),
       :ok <- perform_local_node_cleanup(account_handle, project_handle, cutoff),
       :ok <- mark_applied(account_handle, project_handle, generation) do
    :ok
  else
    true -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

This gives each node replayability without letting one broken project block discovery of later events.

---

## Tests I would add

## Active/published state semantics

- failed cleanup clears active state without leaving a published barrier behind
- published cleanup barrier is only visible after successful publication
- duplicate workers still use active cleanup cutoff for immediate local cleanup

## Barrier-aware replication

- shipper drops stale pending rows when active cleanup exists
- shipper drops stale pending rows when published cleanup exists
- bootstrap skips shared rows behind published cleanup barrier
- steady-state poller skips shared rows behind published cleanup barrier
- rows at or below published barrier cannot be reintroduced to shared state

## Publication replay

- node that missed direct cleanup request later cleans local KV via apply worker
- node that missed direct cleanup request later cleans local disk via apply worker
- node that missed direct cleanup request later cleans `cache_artifacts` metadata via apply worker
- one broken project does not stop discovery of later published cleanup events
- per-project generation tracking prevents duplicate local apply

## Metadata cleanup

- disk cleanup reports exactly deleted keys
- cleanup deletes `cache_artifacts` rows only for actually deleted files
- metadata for newer files remains intact

## GC behavior

- GC deletes rows older than published cleanup cutoff
- GC does not delete rows newer than cutoff
- GC runs in bounded PostgreSQL-compatible batches

## End-to-end behavior

- current CLI fanout path still works unchanged
- one accepted cleanup request is enough for eventual cluster convergence
- CLI command success semantics remain unchanged

---

## Final recommendation

If I had to summarize the corrected redesign in one sentence:

> **Keep the CLI contract and fanout fast path, but make published project cleanup state — together with barrier-aware replication, exact local replay, and background GC — the real distributed cleanup primitive.**

That gives you:

- correctness when nodes miss fanout
- a fix for the current failed-cleanup barrier bug
- less write amplification on the cleanup hot path
- a cleaner separation between in-progress coordination and completed cleanup publication
- exact local metadata cleanup
- a design that can remove per-entry tombstones without creating a stale-row rematerialization hole
