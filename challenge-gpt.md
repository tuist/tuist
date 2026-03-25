# Challenge to `plan.md`

## State of the bookmark

- Current working copy is **not on the bookmark**.
- Current revisions:
  - `@` = `bbec36e1` — empty
  - `@-` = `a396a703` — empty
  - nearest bookmark below = `push-rutomsmrzrks` at `d90ea911`
- `push-rutomsmrzrks` exists locally, in git, and on origin.
- Working copy is clean.
- The bookmark is **18 commits ahead of `main`**.

Relevant commits already on the bookmark:

- `ddcf2697` — `fix(cache): harden distributed cleanup retry and deletion paths`
- `8faf8129` — `fix(cache): harden distributed cleanup coordination`
- `1f6d9a0d` — `fix(cache): use database time for distributed KV coordination`
- `d90ea911` — `perf(cache): thread poller watermark to avoid redundant SQLite reads`

Validation on the bookmark is green:

- `cd cache && mix test` → 486 tests, 0 failures
- `cd cache && mix credo` → no issues
- `cd cache && mix format --check-formatted` → clean

## Immediate concern on the bookmark

`cache/lib/cache/key_value_entries.ex:322` changed the replay-safety signature hash from:

- `:crypto.hash(:sha256, payload)`

to:

- `:erlang.phash2(payload)`

That signature is used for replay-safe pending remote batch handling. `phash2` is a small non-cryptographic hash, so collisions are materially more plausible than with SHA-256. A collision here could make a different batch look like an already-applied batch. Tests pass, but there does not appear to be targeted coverage for collision safety.

## What the plan gets right

The direction is good in several places:

- The **missed-fanout node** problem is real.
  - Today, tombstones converge local KV metadata, but they do **not** cause local disk cleanup on nodes that missed the direct cleanup request.
- The `cache_artifacts` consistency gap is real.
  - `Cache.CleanProjectWorker` deletes project files through `Disk.delete_project_files_before/4`, but does not precisely delete matching `cache_artifacts` metadata.
- `projects.last_cleanup_at` is overloaded.
- Reducing shared write amplification during project cleanup is a worthwhile goal.

## Main challenges to the plan

### 1. Removing tombstones is unsafe unless replication also understands published cleanup barriers

This is the biggest gap in the proposal.

Current bootstrap only materializes shared rows where `deleted_at IS NULL`:

- `cache/lib/cache/key_value_replication_poller.ex:171`

Current remote apply path is explicitly tombstone-aware:

- `cache/lib/cache/key_value_entries.ex:144`
- `cache/lib/cache/key_value_replication_poller.ex:228`

If the system stops writing per-entry tombstones but keeps old shared rows around until background GC deletes them, then a:

- fresh node
- restarted node
- lagging node with an old watermark

can still rematerialize rows that should already be considered cleaned, at least temporarily, before a new project cleanup replay mechanism runs.

So the proposal is incomplete unless it also changes:

- bootstrap filtering
- normal replication poller filtering
- likely shared write / shipper conflict behavior

so they all honor a project-level published cleanup barrier before background GC has physically removed old rows.

### 2. The sample replay poller misses current local side effects

Current local cleanup does more than delete local KV rows. It also clears:

- `KeyValueAccessTracker`
- `Cachex`

That behavior currently happens through `CleanProjectWorker` local invalidation helpers.

The sample `ProjectCleanupPoller` in the plan uses an `on_deleted_keys` callback that does nothing, so a missed node replay would leave stale:

- in-memory cache entries
- lineage/tracker state

The new replay path needs to reuse the same local cleanup side effects as the current worker, not a simplified delete-only version.

### 3. A single global replay watermark can be blocked by one bad project

The plan advances the watermark only after local apply succeeds.

That means one project with a persistent local failure, such as:

- a disk traversal failure
- a permission issue
- a stat error

can block replay for all later cleanup events behind it.

This matters because the current code intentionally treats disk traversal/stat problems as real errors now, not silent partial success.

A better shape is:

- a lightweight poller that discovers new published generations
- a unique Oban job per project/generation for heavy local cleanup
- local tracking of the last applied generation per project

That avoids one broken project stalling global replay.

### 4. The lease-token change is a risky rollout coupling

The current distributed coordination model is based on:

- `projects.last_cleanup_at`
- `projects.cleanup_lease_expires_at`

The plan proposes changing lease identity from timestamp to token at the same time that it introduces published cleanup state.

That is a lot of moving parts for a rolling deploy. Mixed old/new nodes would still need to coordinate correctly. If new nodes stop using the same lease identity as old nodes, cross-version mutual exclusion gets harder.

A safer sequence is:

1. keep current lease semantics
2. add published cleanup state alongside them
3. only revisit tokenized coordination later if it still feels necessary

The important win is separating active coordination from published cleanup state. The token migration is optional.

### 5. The “O(1)” claim is too strong

The proposal reduces **shared write amplification on the hot cleanup path**. That is true.

But total cleanup work is still not O(1), because the system still needs:

- local KV scanning/deletion on each node
- local disk scanning/deletion on each node
- later background GC of shared rows

So the real claim should be narrower:

- cleanup publication can become O(1) per project in the shared store
- not total cleanup work overall

### 6. The plan is missing index work

If the system adds:

- polling by `cleanup_published_at`
- background GC by project plus cutoff

it likely also needs new indexes.

Current shared entry indexes do not cover the GC shape suggested in the plan.

Expected additions would be along the lines of:

- `projects(cleanup_published_at, account_handle, project_handle)`
- `key_value_entries(account_handle, project_handle, source_updated_at)`

Without those, the new polling/GC paths risk becoming expensive.

### 7. The GC SQL is still conceptual, not implementation-ready

The plan sketches a `DELETE ... LIMIT 1000` pattern. In PostgreSQL that is not directly valid in the exact form shown. It would need a CTE or subquery approach.

That does not invalidate the direction, but it means the GC section is still a design sketch rather than a ready implementation plan.

### 8. Cutoff semantics need to stay explicit

The plan phrases cleanup semantically as:

> everything in `account/project` at or before cutoff `T` is dead

That is not literally how all stores behave today.

Current behavior differs by store:

- shared KV tombstoning uses `<= cutoff`
- disk cleanup uses **strictly before** the cutoff second
- S3 cleanup uses **strictly before** the cutoff second

So any redesign needs to preserve that distinction, or it risks subtle same-second mismatches.

### 9. CLI correctness and CLI success are still different things

The plan correctly tries to make one accepted cleanup request enough for eventual correctness.

But the CLI still fans out to all cache endpoints and waits for all of them:

- `cli/Sources/TuistKit/Services/CleanService.swift:174`

So even after the redesign:

- cluster convergence could succeed with one accepting node
- the user command could still fail if one endpoint is down

That may be acceptable, but the plan should state it explicitly.

### 10. The plan starts from a slightly stale view of the current implementation

The current bookmark already improved several cleanup behaviors the plan presents as if they were still open:

- duplicate workers already perform node-local cleanup while shared cleanup is in progress
- lease renewals are threaded through local cleanup batches
- cleanup cutoff lookup is already more bounded

The plan should be rewritten against the current hardened bookmark state, not the earlier design.

## If this is one implementation, the minimum bar is higher

If the intent is a single implementation rather than multiple rollout phases, then the proposal still needs to define one coherent change set that lands **all** of the required safety properties together.

In one implementation, it is not enough to add a published cleanup event and a replay poller. The same implementation must also ensure that:

- replication bootstrap does **not** rematerialize rows that are already behind a published project cleanup barrier
- normal replication polling does **not** rematerialize rows that are already behind that barrier
- shipper-side stale row suppression uses the same effective barrier semantics
- missed-node replay performs the same local side effects as the current cleanup worker, including in-memory invalidation and tracker cleanup
- local `cache_artifacts` metadata is cleaned exactly for files that were actually deleted
- the shared store has the indexes needed for `cleanup_published_at` polling and project-scoped cutoff GC
- the GC query is specified in a real PostgreSQL-compatible batched form
- mixed old/new cleanup semantics are not required for correctness during rollout, or the plan explicitly explains how cross-version coordination stays safe

If those pieces are not part of the same implementation, then the design is still incomplete.

## Bottom line

The direction is good, but the plan is **not ready as written**.

The key missing piece is:

> per-entry tombstones cannot be removed safely unless the same implementation also teaches replication bootstrap and polling to honor project-level published cleanup barriers.

Independent of the redesign plan, the current bookmark also has one concrete issue worth revisiting first:

- the change from SHA-256 to `:erlang.phash2/1` in remote batch replay signatures

My recommendation is:

1. keep challenging the plan on single-implementation completeness, especially around barrier-aware replication
2. require the one implementation to cover bootstrap, steady-state polling, replay, local metadata cleanup, and GC/indexing together
3. revisit the `phash2` replay-signature change on the current bookmark before piling on more distributed cleanup complexity
