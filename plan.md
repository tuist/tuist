# Plan: chunked local apply for distributed KV replication

## Summary

The current distributed KV replication poller is still doing too much SQLite work per page:

- it fetches a page of remote rows in `cache/lib/cache/key_value_replication_poller.ex`
- then applies them **one row at a time**
- and each alive-row materialization opens its own `KeyValueRepo.transaction/1` in `cache/lib/cache/key_value_entries.ex`

That was acceptable as an initial implementation, but it is not the right steady-state design for sustained production load.

The immediate mitigations already in place reduce the blast radius:

- start KV dependencies before the endpoint
- `KEY_VALUE_POOL_SIZE=1` in prod
- treat `"Database busy"` as lock contention
- stop the poller page early on busy instead of crashing
- throttle repeated access bumps more aggressively

Those changes make the system safer, but they do **not** remove the core throughput problem. The longer-term fix is to refactor local replication materialization so the poller applies remote rows in **small committed chunks with fewer SQLite transactions and batched upserts/deletes**.

The primary focus of this plan is **steady-state replication on existing nodes**. Bootstrap behavior is secondary and should not block the main throughput fix.

---

## Context

### Incident context

The distributed KV rollout exposed two separate issues:

1. **startup-order / readiness issue** caused the 502 spike and crash-loop behavior
2. **SQLite contention issue** showed up after startup, with errors like `Exqlite.Error: Database busy`

The startup problem is addressed separately.

For SQLite contention, the current changes are mostly defensive. They make the system more tolerant of lock pressure, but the poller still creates a lot of unnecessary write pressure because it treats each replicated row as an isolated SQLite operation.

### Why the current implementation is expensive

Today, `Cache.KeyValueReplicationPoller`:

- fetches up to `@page_size` remote rows (`1000`)
- iterates through them sequentially
- for each non-deleted row, calls `KeyValueEntries.materialize_remote_entry/1`
- for each deleted row, calls `KeyValueEntries.delete_local_entry_if_not_pending/1`

And `KeyValueEntries.materialize_remote_entry/1` currently:

- loads the local row by key
- merges local/remote state
- wraps the operation in its own `KeyValueRepo.transaction/1`

So a single page can translate into hundreds or thousands of small SQLite write transactions.

That has several costs:

- repeated lock acquisition/release
- repeated transaction overhead
- more WAL churn
- more opportunities to collide with request-path reads/writes
- more chances for the poller to hit a busy error in the middle of a page

This is why the recent mitigations are only partial. Even with `KEY_VALUE_POOL_SIZE=1`, we are still spending too much time entering and leaving transactions.

---

## Goal

Refactor distributed KV local materialization so that a poller page is applied through **fixed-size chunked batch writes** instead of per-row transactions.

The desired outcome is:

- **fewer SQLite transactions**
- **batched upserts for alive rows**
- **batched deletes for tombstones**
- **correct watermark advancement only through committed work**
- **safe retry behavior when busy or when post-commit side effects fail**
- **lower lock contention under sustained load**

---

## Non-goals

This plan does **not** attempt to:

- disable distributed KV mode
- move the local store away from SQLite
- redesign the remote shared-store schema
- change merge semantics between local pending writes and remote alive rows
- change tombstone semantics beyond preserving the current pending-aware local delete rule
- redesign bootstrap product behavior beyond optionally reusing the new batch primitive
- add new timeout-tuning knobs in the first pass
- solve every future throughput issue in one step

The focus here is specifically the **steady-state local apply path** inside the replication poller.

---

## Current correctness rules we must preserve

Any batching refactor must keep these invariants:

1. **Watermark ordering stays `(updated_at, key)`**
   - The poller query is ordered by `updated_at ASC, key ASC`
   - The watermark must only advance through rows that were definitely committed locally and whose post-commit side effects completed successfully

2. **Local pending writes still win when they should**
   - `merge_remote_into_local/2` already protects a newer local pending row from being overwritten by an older remote row
   - batching must preserve exactly that rule

3. **Remote tombstones keep the current pending-aware delete rule**
   - current behavior only deletes local rows when `replication_enqueued_at IS NULL`
   - batched tombstone deletes must preserve that exact rule
   - this plan does **not** change tombstone semantics to override pending local rows

4. **Cache invalidation and access-tracker updates happen only after a successful DB commit**
   - `Cachex.del/2`
   - `KeyValueAccessTracker.mark_shared_lineage/1`
   - `KeyValueAccessTracker.clear/1`
   - these side effects should happen only after the underlying DB work is committed successfully

5. **If post-commit side effects or watermark persistence fail, we do not advance the watermark**
   - at-least-once replay of the committed chunk on the next poll is acceptable
   - correctness wins over avoiding duplicate work

6. **Busy handling must remain safe**
   - if a chunk cannot be committed because SQLite is busy, the poller should stop cleanly and retry later
   - it must not skip rows or advance the watermark past uncommitted work

7. **Existing bounded bootstrap behavior must remain safe if it is switched to batching later**
   - bootstrap currently loads most-recently-accessed alive rows until the local size cap is reached
   - if we reuse the batch primitive there, budget accounting can remain approximate
   - bootstrap work is secondary and should not block the steady-state fix

---

## Concrete execution decisions

These choices remove ambiguity for the first implementation:

- **Fixed local apply chunk size:** `100` rows
- **Chunk atomicity:** each chunk is all-or-nothing
- **Transaction boundary:** local prefetch, merge computation, batched upsert, and batched delete all run inside the same SQLite transaction
- **Busy handling shape:** `apply_remote_batch/1` returns either `{:ok, result}` or `{:error, :busy}`
- **Watermark cadence:** persist watermark after **each committed chunk**, not once per page
- **Side-effect ordering:** DB commit first, then cache / ETS side effects, then watermark persistence
- **Replay policy:** if side effects or watermark write fail after commit, stop processing the page, leave watermark unchanged for that chunk, and retry later
- **Timeout behavior:** first pass keeps the current repo timeout / busy handling behavior; no new poller-specific busy-timeout wrapper yet
- **Configuration:** chunk size is internal and hard-coded for the first rollout

---

## High-level design

### Decision 1: batch within a page, not across the whole poll run

The poller should still fetch ordered pages from the remote store, but it should apply each page in **smaller local chunks**.

Why:

- keeps watermark semantics straightforward
- limits how much work is lost on a single busy error
- avoids building huge `insert_all` payloads
- makes SQLite parameter limits easier to respect

A fixed starting chunk size of **100 rows** is small enough to stay well below SQLite bind-parameter limits while still reducing transaction count dramatically.

### Decision 2: compute final row state in Elixir, then batch-write it

We should preserve the existing merge logic by computing the final local state in memory before writing.

That means the new batch apply flow should:

1. partition the chunk into alive rows and tombstones
2. open one SQLite transaction for the chunk
3. prefetch all local rows for the chunk keys inside that transaction
4. for alive rows:
   - compute final local row contents using the same rules as `merge_remote_into_local/2`
5. write the alive row set with **one batched upsert**
6. delete tombstoned keys with **one batched delete query**
7. commit the transaction

This is safer than trying to re-express all merge rules as complex SQL.

### Decision 3: keep external side effects out of the DB transaction

The DB transaction should only do SQLite work.

After a batch transaction commits, the caller then:

- invalidates `Cachex` keys
- marks shared lineage for alive rows
- clears lineage/throttle entries for tombstone rows
- persists the watermark for that chunk

If any post-commit side effect or watermark write fails, the poller stops processing the page and retries later without advancing the watermark for that chunk.

---

## Proposed API changes

Introduce a batch-oriented API in `cache/lib/cache/key_value_entries.ex`.

Suggested shape:

```elixir
apply_remote_batch(rows)
```

Where `rows` is a list of `%Cache.DistributedKV.Entry{}` values from the poller.

Suggested contract:

```elixir
{:ok,
 %{
   processed_count: integer(),
   inserted_count: integer(),
   payload_updated_count: integer(),
   access_updated_count: integer(),
   deleted_count: integer(),
   last_processed_row: Entry.t() | nil,
   invalidate_keys: [String.t()],
   mark_lineage_keys: [String.t()],
   clear_lineage_keys: [String.t()]
 }}

{:error, :busy}
```

Important details:

- `processed_count` counts all rows in the committed chunk
- `inserted_count` counts alive rows that created a new local row
- `payload_updated_count` counts alive rows whose payload or `source_updated_at` changed locally
- `access_updated_count` counts alive rows that only changed access metadata
- `deleted_count` counts actual local rows deleted by tombstone processing
- `invalidate_keys` should include:
  - alive rows that were inserted or payload-updated
  - all tombstone row keys, matching current behavior
- `mark_lineage_keys` should include alive row keys
- `clear_lineage_keys` should include tombstone row keys, matching current behavior

The result describes exactly what committed and exactly which post-commit side effects still need to run.

---

## Proposed write path

### 1. Partition the chunk

For each chunk from the poller page:

- `alive_rows = Enum.filter(rows, &is_nil(&1.deleted_at))`
- `deleted_rows = Enum.reject(rows, &is_nil(&1.deleted_at))`
- `keys = Enum.map(rows, & &1.key)`

### 2. Open a single transaction for the chunk

Inside one `KeyValueRepo.transaction/1`:

- prefetch local rows for `keys`
- build final alive-row maps in memory
- perform one `insert_all` for alive rows
- perform one `delete_all` for tombstones
- return the committed result metadata

Local prefetch is intentionally inside the same transaction as the writes so the chunk operates on a consistent local snapshot.

### 3. Build the batched upsert payload for alive rows

For each alive remote row:

- if there is no local row, build a new inserted row
- if there is a local row, compute the final state using the same logic as today
- preserve `replication_enqueued_at` when local pending state must survive
- only overwrite payload / source version when the remote row wins
- always apply the correct `last_accessed_at = max(local, remote)` logic

The implementation should reuse or extract the current merge logic instead of rewriting the semantics.

### 4. Use `insert_all` with `on_conflict`

Once the final row maps are built, write them in one call:

```elixir
KeyValueRepo.insert_all(
  KeyValueEntry,
  rows,
  on_conflict: {:replace, [:json_payload, :last_accessed_at, :source_updated_at, :replication_enqueued_at, :updated_at]},
  conflict_target: [:key]
)
```

Exact column list may need adjustment, but the key point is:

- **one upsert statement per chunk**, not one transaction per row

Important detail:

- `inserted_at` should be set for new rows
- `inserted_at` for existing rows should stay unchanged
- so `inserted_at` should not be blindly replaced on conflict

### 5. Use one `delete_all` for tombstones

For deleted remote rows in the chunk, delete in one query:

```elixir
from(entry in KeyValueEntry,
  where: entry.key in ^deleted_keys,
  where: is_nil(entry.replication_enqueued_at)
)
|> KeyValueRepo.delete_all()
```

That preserves the current tombstone semantics while collapsing many delete calls into one statement.

### 6. Commit the chunk, then run side effects

After the chunk transaction commits successfully, the poller:

1. invalidates cache entries in `invalidate_keys`
2. marks lineage for `mark_lineage_keys`
3. clears lineage / throttle entries for `clear_lineage_keys`
4. persists watermark for `last_processed_row`

If any of steps 1-4 fail:

- stop processing the current page
- leave watermark unchanged for that chunk
- retry later

This preserves correctness at the cost of acceptable duplicate work.

---

## Poller refactor

`cache/lib/cache/key_value_replication_poller.ex` should move from per-row apply to chunked apply.

### New flow for `apply_one_page/2`

1. fetch up to `@page_size` remote rows
2. split the rows into local apply chunks of 100
3. for each chunk:
   - call the new batch API
   - if the chunk returns `{:ok, result}`:
     - run post-commit side effects from the returned key lists
     - persist watermark for `result.last_processed_row`
     - emit lag telemetry based on that row
     - accumulate counters
   - if the chunk returns `{:error, :busy}`:
     - stop processing the page
     - leave that chunk and later rows for the next poll
   - if post-commit side effects or watermark persistence fail:
     - stop processing the page
     - leave watermark at the last previously successful chunk
     - retry the committed-but-unwatermarked chunk on the next poll
4. continue until the page is exhausted or processing stops early

### Important watermark rule

The poller must never treat a fetched chunk as processed unless:

- its SQLite transaction committed
- its post-commit side effects completed
- its watermark was persisted

That means:

- if chunk 1 fully succeeds and chunk 2 hits busy, watermark advances through chunk 1 only
- if chunk 1 DB commit succeeds but post-commit side effects fail, watermark does **not** advance through chunk 1
- in either case, unwatermarked rows are retried on the next poll

This keeps the poller safe under both contention and post-commit failures.

---

## Bootstrap

Bootstrap is **not** the primary driver for this work. The incident is about existing nodes under steady-state replication load.

For this plan, bootstrap should be treated as **bounded bootstrap**:

- it remains capped by the local size limit
- budget accounting can remain approximate using payload byte sizes
- it should not jump the watermark when it stops because of busy
- its semantics do not need to block the steady-state poller refactor

Recommended handling:

- land the steady-state batch apply primitive first
- optionally reuse it for bootstrap afterward
- if bootstrap is switched, preserve the current “most recently accessed rows until cap” behavior rather than redesigning bootstrap semantics in the same change

---

## Implementation steps

### Phase 1: add the batch apply primitive

In `Cache.KeyValueEntries`:

- add `apply_remote_batch/1`
- reuse/extract merge helpers so row semantics stay identical
- compute explicit per-status counters
- return deterministic side-effect key lists
- keep the old per-row helpers in place until the poller is switched

### Phase 2: switch the steady-state poller to the batch primitive

In `Cache.KeyValueReplicationPoller`:

- replace row-by-row `Enum.reduce_while` logic with chunked apply
- use a fixed chunk size of 100
- persist watermark after each successful chunk
- stop early on busy
- stop early on post-commit side-effect or watermark errors
- keep row-based telemetry, but update it from batch results

### Phase 3: optionally switch bootstrap to the batch primitive

- this is follow-up work, not the blocker for the incident
- preserve current bounded bootstrap behavior if switched
- keep approximate budget accounting
- stop cleanly on busy without watermark jump

### Phase 4: add instrumentation and rollout aids

Add telemetry/logging around:

- `chunk_size`
- `chunks_committed`
- `rows_processed`
- `rows_inserted`
- `rows_payload_updated`
- `rows_access_updated`
- `rows_deleted`
- `rows_retried_due_to_busy`
- `chunk_apply_duration_ms`
- `sqlite_busy_count`
- `post_commit_retry_count`

This is important because once the refactor lands, we want hard evidence that contention actually drops.

---

## Testing plan

### Unit and integration coverage to add

#### `Cache.KeyValueEntries`

- batch inserts new rows correctly
- batch updates existing rows correctly
- newer local pending rows still win over stale remote rows
- `last_accessed_at` merging stays correct
- tombstones delete only non-pending rows
- tombstones still report cache invalidation / lineage clearing keys even when delete count is zero
- mixed chunks with inserts, updates, and deletes commit correctly
- busy errors return `{:error, :busy}` and leave the chunk uncommitted

#### `Cache.KeyValueReplicationPoller`

- processes a page through multiple committed chunks
- advances the watermark after each successful chunk
- stops early on busy without crashing
- retries the uncommitted remainder on the next poll
- if post-commit side effects fail, does not advance watermark for that chunk
- keeps telemetry counts correct for partial pages

#### Bootstrap

If bootstrap is switched in this work:

- respects the configured local cap with approximate accounting
- stops on busy without corrupting bootstrap state
- does not jump the watermark when bootstrap stops on busy

### Important test style note

At least part of this should be tested against the real SQLite-backed `KeyValueRepo`, not only mocks.

This refactor is specifically about SQLite behavior and transaction shape, so some integration coverage is worth the extra cost.

---

## Rollout and validation

### Before rollout

- land the steady-state refactor behind the existing distributed KV flow without changing product behavior
- compare emitted telemetry before and after in staging/canary
- specifically watch:
  - poll duration
  - busy error frequency
  - rows processed per poll
  - local store size growth
  - request latency on cache endpoints during replication

### After rollout

For production validation, monitor:

- `Database busy` frequency
- replication lag
- poller restarts/crashes
- 5xx rate on cache nodes
- rows applied per second under steady-state load
- whether `KEY_VALUE_POOL_SIZE=1` still appears necessary at the same strictness level

This plan should reduce the pressure enough that the defensive mitigations become less critical, even if they remain in place.

---

## Risks and open questions

### 1. SQLite parameter limits

A naive `insert_all` over too many rows can exceed SQLite parameter limits.

Mitigation:

- keep local apply chunks fixed at 100 rows for the first rollout
- tune later based on real measurements

### 2. Insert/update timestamp semantics

We must be careful not to clobber `inserted_at` for existing rows during upsert.

Mitigation:

- only replace columns that should change on conflict
- verify with integration tests

### 3. Side effects after commit

`Cachex.del` and ETS lineage updates are external to SQLite.

Mitigation:

- treat DB commit as the source of truth for replay
- run side effects only after successful commit
- do not advance watermark when side effects fail
- keep returned side-effect lists deterministic and idempotent-friendly

### 4. Metrics continuity

Current telemetry counts rows materialized/deleted. After batching, those metrics must still mean something stable.

Mitigation:

- make counters explicit (`inserted`, `payload_updated`, `access_updated`, `deleted`)
- add chunk-level telemetry as additional signal, not a replacement

### 5. Scope creep

It would be easy to mix this refactor with unrelated changes to shipping, access tracking, cleanup semantics, bootstrap redesign, or remote schemas.

Decision:

- keep the first pass narrowly focused on steady-state local apply batching only

---

## Recommended first implementation shape

The lowest-risk version of this refactor is:

1. add `KeyValueEntries.apply_remote_batch/1`
2. prefetch local rows once per chunk inside the chunk transaction
3. build final upsert row maps in Elixir
4. do one `insert_all` for alive rows
5. do one `delete_all` for tombstones using the current pending-aware rule
6. commit the chunk in one SQLite transaction
7. run cache / ETS side effects after commit
8. persist watermark after each fully successful chunk
9. stop the page on busy or post-commit failure and retry later

That gives the main benefit quickly without trying to redesign the whole replication subsystem.

---

## Definition of done

This work should be considered done when all of the following are true:

- the steady-state poller no longer opens one SQLite transaction per replicated alive row
- steady-state local replication applies rows in chunked batch transactions
- alive rows use batched upserts
- tombstones use batched deletes with the current pending-aware semantics
- watermark advancement remains correct under partial progress, busy contention, and post-commit retry conditions
- test coverage proves the previous merge semantics are preserved
- telemetry shows reduced busy frequency and better sustained replication throughput

Bootstrap batching is desirable, but it is not the blocking success criterion for this incident-driven refactor.

---

## Bottom line

The recent fixes make distributed KV **less fragile**.

This plan is about making steady-state replication **efficient enough to handle sustained load**.

The key change is simple in principle:

- stop treating each remote row as its own SQLite transaction
- apply remote rows in small committed chunks with batched upserts and deletes

That is the longer-term fix that should materially reduce SQLite contention in production.