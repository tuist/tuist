# Combined challenge to `plan.md`

## Snapshot of the current bookmark

- Current working copy is **not on the bookmark**:
  - `@` = `bbec36e1` — empty
  - `@-` = `a396a703` — empty
  - nearest bookmark below = `push-rutomsmrzrks` at `d90ea911`
- `push-rutomsmrzrks` exists locally, in git, and on origin.
- The bookmark is **18 commits ahead of `main`**.
- Validation on the bookmark is green:
  - `cd cache && mix test` → 486 tests, 0 failures
  - `cd cache && mix credo` → no issues
  - `cd cache && mix format --check-formatted` → clean

Relevant bookmark commits already hardened the current implementation:

- `ddcf2697` — `fix(cache): harden distributed cleanup retry and deletion paths`
- `8faf8129` — `fix(cache): harden distributed cleanup coordination`
- `1f6d9a0d` — `fix(cache): use database time for distributed KV coordination`
- `d90ea911` — `perf(cache): thread poller watermark to avoid redundant SQLite reads`

That matters because the plan should be challenged against the **current** hardened state, not an older mental model.

---

## Assessment of `challenge-claude.md` against my earlier challenge

`challenge-claude.md` adds several strong points that should absolutely be kept:

1. **It correctly elevates the failed-cleanup barrier bug.**
   - This is stronger than my original framing and should be treated as a top-tier issue.
   - Today `expire_project_cleanup_lease/3` clears the lease expiry but leaves `last_cleanup_at` in place, while the shipper still uses `last_cleanup_at` as a cleanup barrier.
   - That means a failed cleanup can permanently suppress valid rows from being replicated.

2. **It correctly calls out that the cleanup cutoff should be owned by the shared DB row, not threaded through caller code.**
   - I agree with this.
   - If the redesign adds `active_cleanup_cutoff_at`, then `publish_project_cleanup` should read that stored cutoff rather than trusting a cutoff parameter passed back in by worker code.

3. **It correctly notes that `published_cleanup_generation` is underspecified.**
   - I agree.
   - Either use it for something concrete, such as local applied-generation tracking, or drop it.

4. **It correctly notes that the GC SQL sketch is not PostgreSQL-ready.**
   - I also raised this.
   - It is not a design blocker, but the plan should not present non-compilable SQL as if it were implementation-ready.

5. **It usefully highlights redundant work after a post-publication crash.**
   - This is a good implementation note.
   - I see it as lower priority than the correctness blockers, but it is real.

Where I would soften `challenge-claude.md`:

- **The sequence-based watermark idea is a good simplification, not a must-have blocker.**
  - A `(cleanup_published_at, account_handle, project_handle)` cursor can be made correct.
  - A monotonic event id would be cleaner, but I would present that as a design improvement, not the core problem.

So the combined view is:

- Claude is strongest on the **failed-cleanup barrier bug** and **DB-owned cutoff**.
- My earlier challenge is strongest on the **barrier-aware replication gap**, **missed local side effects**, **single-poller poison-pill risk**, **cross-version coordination risk**, and the **current bookmark’s `phash2` regression risk**.

---

## Verified facts both reviews agree on

These claims from `plan.md` or around it are supported by the current code:

1. **`last_cleanup_at` is overloaded.**
   - `cache/lib/cache/distributed_kv/project.ex`
   - `cache/lib/cache/distributed_kv/cleanup.ex`
   - It is currently serving as lease identity, cleanup cutoff, shipper barrier, and the only durable cleanup marker.

2. **Per-entry tombstoning is O(project keys).**
   - `cache/lib/cache/distributed_kv/cleanup.ex`
   - `tombstone_project_entries/3` updates all matching shared rows.

3. **Local disk cleanup still depends on fanout.**
   - `cache/lib/cache/clean_project_worker.ex`
   - `cache/lib/cache/key_value_replication_poller.ex`
   - Poller side effects clear local KV/cache state, but they do not clean disk.

4. **`cache_artifacts` metadata is not cleaned by project cleanup today.**
   - `cache/lib/cache/clean_project_worker.ex`
   - `cache/lib/cache/cache_artifacts.ex`
   - `cache/lib/cache/disk.ex`

5. **`Disk.delete_project_files_before/4` cannot currently report deleted keys.**
   - It supports `on_progress:` but not `on_deleted_keys:` and returns only `{:ok, count}`.

These are solid foundations for the challenge.

---

## Combined challenge: the most important issues

## 1. The current system already has a failed-cleanup barrier bug

This should be the first challenge because it is not just architectural awkwardness; it is a real correctness problem in the current design.

Today:

- `begin_project_cleanup/2` stores `last_cleanup_at`
- `expire_project_cleanup_lease/3` expires the lease but does **not** clear `last_cleanup_at`
- `latest_project_cleanup_cutoffs/1` still returns `last_cleanup_at` to the shipper
- the shipper drops rows at or before that cutoff

So if cleanup fails after the barrier has been established, valid rows can be suppressed forever even though shared deletion never completed.

That means the plan’s active-vs-published split is not merely “cleaner”; it fixes a concrete bug.

This point should be stated explicitly in the challenge.

---

## 2. Tombstones cannot be removed unless replication becomes barrier-aware everywhere

This remains the biggest gap in the plan as written.

Current shared replication behavior is tombstone-based:

- bootstrap materializes only rows with `deleted_at IS NULL`
  - `cache/lib/cache/key_value_replication_poller.ex`
- steady-state apply treats rows with `deleted_at` as deletions
  - `cache/lib/cache/key_value_entries.ex`
  - `cache/lib/cache/key_value_replication_poller.ex`

If the redesign stops writing tombstones but delays physical shared-row deletion to background GC, then old rows are still present in the shared store. Without additional changes:

- a fresh node
- a restarted node
- a lagging node with an old watermark

can rematerialize rows that are already semantically dead.

So a one-shot implementation must make the following paths barrier-aware in the same change set:

- replication bootstrap
- normal replication polling
- shipper stale-row suppression
- shared conflict/materialization logic where relevant

This is the single biggest completeness gap in `plan.md`.

---

## 3. The replay path must reproduce the current local side effects, not just delete rows

The sample replay logic in `plan.md` is too weak.

Current project cleanup does more than remove SQLite rows. It also clears:

- `KeyValueAccessTracker`
- `Cachex`

through the local invalidation helpers in `cache/lib/cache/clean_project_worker.ex`.

If a missed-node replay only deletes KV rows and disk files, it will leave stale:

- in-memory cache entries
- access-tracker / lineage state

So the replay path must reuse the same local cleanup semantics as the normal cleanup worker, including all deletion side effects.

---

## 4. `cache_artifacts` cleanup has to be exact in the same implementation

Both reviews agree this is real.

If project cleanup is supposed to leave the node locally consistent, then it cannot:

- delete files from disk
- but leave stale `cache_artifacts` metadata behind

The plan correctly spots that `Disk.delete_project_files_before/4` currently cannot report deleted keys. That means the redesign cannot stop at publication/replay semantics; it must also either:

- add `on_deleted_keys:` to disk cleanup, or
- otherwise make exact metadata deletion possible

This is not a nice-to-have. It is part of making project cleanup actually complete.

---

## 5. A single global replay watermark is vulnerable to one broken project

This remains one of my biggest challenges to the plan.

If one poller reads published cleanup events and only advances the watermark after full local apply succeeds, then a project with a persistent local failure can block all later cleanup events behind it.

That is particularly relevant because current disk cleanup intentionally surfaces traversal/stat failures as real errors.

A more robust shape is:

- lightweight poller discovers new published cleanup events
- poller enqueues a unique local Oban job per project/generation
- local state records last-applied generation per project

This also gives a natural home for `published_cleanup_generation` if that field is kept.

This is a better one-implementation design than doing heavy disk work inline in a single GenServer replay loop.

---

## 6. The shared DB row should own the cutoff; caller code should not

This is a strong point from `challenge-claude.md` and should be merged in.

If the redesign adds:

- `active_cleanup_cutoff_at`
- `active_cleanup_token`

then the cleanup cutoff should be established once in shared state and read back from shared state.

So `publish_project_cleanup/…` should not accept an arbitrary caller-provided cutoff and trust it. It should verify the active lease/token and publish the cutoff stored in the row.

That avoids subtle divergence between:

- the cutoff used in local cleanup
- the cutoff published for replay/barrier semantics

and makes double-processing from fanout-plus-replay safer.

---

## 7. The tokenized lease redesign is optional, but rollout safety is not

I still think the plan is trying to change too much at once by combining:

- active/published state split
- tokenized lease identity
- publication-based replay
- tombstone removal
- GC redesign

Even if the author wants “one implementation,” distributed rollout still matters because deployments are rolling by nature. Mixed old/new nodes can coexist during rollout.

So the challenge here is:

- if the implementation changes the lease identity model, it must explain how old and new nodes continue to coordinate safely during deployment
- otherwise, keep the existing lease identity semantics and only split active vs published state

The core need is the active/published split. The token is optional.

---

## 8. The GC/indexing section is not implementation-ready yet

This point is supported by both reviews.

The plan needs to specify:

- PostgreSQL-valid batched GC SQL
- indexes that support the new read/write patterns

At minimum, the design likely needs indexing for:

- polling by `cleanup_published_at`
- project-scoped GC by cleanup cutoff

For example, likely something like:

- `projects(cleanup_published_at, account_handle, project_handle)`
- `key_value_entries(account_handle, project_handle, source_updated_at)`

The exact index set can be debated, but the current plan is underspecified here.

---

## 9. `published_cleanup_generation` must either be used concretely or dropped

This is a good challenge from Claude.

As currently described in `plan.md`, `published_cleanup_generation` is mentioned but not really used.

That is fine if it becomes the local idempotency mechanism:

- local per-project applied-generation tracking
- unique replay jobs keyed by project + generation
- skip duplicate local work when fanout already handled the same generation

If not, it looks like dead weight.

So the combined challenge should be:

> either make generation the local replay/idempotency primitive, or remove it from the design.

---

## 10. The watermark cursor can be correct as proposed, but a monotonic event id may be cleaner

This is where I would merge Claude’s point, but downgrade it from blocker to design improvement.

A tuple cursor based on:

- `cleanup_published_at`
- `account_handle`
- `project_handle`

can be correct.

A monotonic event id would be simpler and easier to reason about.

So I would not say the plan is wrong because it uses a tuple cursor. I would say:

- tuple cursor is acceptable if carefully indexed and implemented
- event id / sequence is a worthwhile simplification if the author wants a cleaner replay mechanism

---

## 11. The plan overstates the “O(1)” win

The plan is right that publication can become O(1) in the shared store.

It is wrong if that gets read as “project cleanup becomes O(1).”

Total work still includes:

- local KV cleanup on nodes
- local disk cleanup on nodes
- background shared-row GC

So the accurate claim is:

- shared cleanup publication can be O(1) per project
- total cluster cleanup work is still proportional to the amount of data to clean

This is a wording issue, not a design blocker, but the challenge should call it out.

---

## 12. CLI correctness and CLI command success are still different

The plan wants one accepted cleanup request to be enough for correctness.

That is a good goal.

But the CLI still fans out to all endpoints and waits for all of them. So even if the redesign makes cluster convergence eventually correct with one accepting node, the command can still fail from the user’s perspective if one endpoint is down.

That may be acceptable. It just needs to be stated honestly.

---

## 13. The current bookmark has an additional unrelated but important risk: `phash2`

This is not directly about the cleanup redesign, but it matters because it is already on the bookmark that the plan is being discussed against.

`cache/lib/cache/key_value_entries.ex` changed replay-safety payload hashing from:

- `:crypto.hash(:sha256, payload)`

to:

- `:erlang.phash2(payload)`

That signature is part of the replay-safe remote batch handling path. `phash2` is a small non-cryptographic hash. A collision here could make a different pending remote batch look like an already-applied one.

That is independent of the cleanup plan, but it is a real bookmark-specific concern that should be revisited before layering on more distributed coordination complexity.

---

## What one implementation must contain to be complete

Since the intent is **one implementation**, the challenge should not talk about phases. It should instead set a single completeness bar.

A one-shot implementation is only credible if it lands all of these together:

1. **Separate active cleanup state from published cleanup state**
   - specifically to fix the failed-cleanup barrier bug

2. **Make replication barrier-aware before removing tombstones**
   - bootstrap
   - steady-state poller
   - shipper suppression

3. **Replay missed cleanups with full local side effects**
   - KV deletion
   - Cachex invalidation
   - KeyValueAccessTracker cleanup
   - disk deletion

4. **Clean `cache_artifacts` exactly for actually deleted files**

5. **Define a replay idempotency mechanism**
   - ideally per-project applied generation if generation is kept

6. **Define DB-owned cutoff semantics**
   - the shared row is the source of truth for the cleanup cutoff

7. **Specify real GC and indexing**
   - PostgreSQL-valid batched delete shape
   - indexes for publication polling and project-scoped cutoff GC

8. **Explain deployment safety**
   - especially if lease identity changes during rollout

If any of those are missing, the design is still incomplete even if the code compiles.

---

## Bottom line

The direction in `plan.md` is good. The diagnosis is mostly right. The current system really does need a project-level publication model rather than fanout-plus-tombstones as the primary correctness story.

But the plan is **not ready as written**.

The most important combined challenge is:

> removing per-entry tombstones is only safe if the same implementation also makes bootstrap, steady-state polling, and stale-row suppression honor project-level published cleanup barriers.

And the most important current-code framing correction is:

> the active-vs-published split is not just architectural cleanup; it fixes a real failed-cleanup barrier bug in the current implementation.

Secondary but important additions are:

- replay must preserve all local invalidation side effects
- `cache_artifacts` cleanup must become exact
- single-poller replay is too fragile without per-project idempotency / job isolation
- `published_cleanup_generation` needs a real job or should be removed
- the current bookmark’s `phash2` replay-signature change should be revisited
