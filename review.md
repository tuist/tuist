# Action Plan

Context: this branch (`cschmatzler/fix-kv-explosion`) makes three substantial changes at once:

1. It moves KV metadata into a dedicated SQLite database (`KeyValueRepo`) so it is isolated from artifact metadata and Oban state in `Cache.Repo`.
2. It introduces a dedicated CAS S3 bucket (`S3_CAS_BUCKET`) with migration-mode fallback reads from the shared cache bucket.
3. It redesigns KV eviction around size thresholds, bounded runtime, cursor-based batching, and SQLite contention handling.

The direction is good. The cold-start migration approach for `KeyValueRepo` is especially pragmatic because it avoids risky data migration work and lets KV state repopulate naturally from traffic. The main remaining work is to tighten correctness around the CAS bucket migration, clean up merge artifacts, and reduce a few maintenance risks introduced by the refactor.

## Priority 1: Fix correctness and merge blockers

### 1. Make CAS fallback trigger only on definite "not found"

Files:
- `cache/lib/cache/s3.ex:68`
- `cache/lib/cache/s3.ex:447`

Problem:
The new CAS fallback path currently falls back to the legacy shared bucket whenever `head_object_exists?/2` returns `false`. Right now that helper returns `false` for all errors, not just `404` / missing-object responses. That means a transient S3 timeout, throttling response, or `5xx` from `S3_CAS_BUCKET` can incorrectly send the request to `S3_BUCKET`, producing a user-visible miss even when the object exists in the primary CAS bucket.

Action:
- Change the HEAD existence check so it distinguishes between:
  - object exists
  - object definitely does not exist
  - request failed for another reason
- Only use fallback-to-legacy-bucket on the definite not-found case.
- For transient or unknown failures, propagate the error or retry instead of pretending the object is absent.

Why this matters:
This is the most important issue because it changes temporary infrastructure failures into incorrect application behavior during the migration window.

Definition of done:
- Presign and download flows use the legacy bucket only after a confirmed not-found from the CAS bucket.
- Non-404 failures no longer produce false misses.
- Tests cover 404 vs timeout / throttling / 5xx behavior.

### 2. Remove tracked SQLite test artifacts

Files:
- `cache/test_key_value.sqlite3`
- `cache/test_key_value.sqlite3-shm`
- `cache/test_key_value.sqlite3-wal`

Problem:
Binary SQLite test files are tracked in git even though `.gitignore` already ignores `test_key_value.sqlite*`. These are repository artifacts, not source.

Action:
- Remove the three tracked SQLite files from version control.
- Confirm `.gitignore` already covers them so they do not come back.

Why this matters:
These files create noisy diffs, make review harder, and do not belong in the repository.

Definition of done:
- The three SQLite files are no longer tracked.

### 3. Remove `changes.md` from the repo root

File:
- `changes.md`

Problem:
This appears to be design or planning material for the branch rather than durable repository documentation.

Action:
- Remove `changes.md` from the repository, or move any valuable rationale into the PR description.

Why this matters:
It keeps the repository focused on long-lived source and documentation rather than temporary planning notes.

Definition of done:
- `changes.md` is no longer part of the change set, and any important rationale is preserved in the PR description if needed.

## Priority 2: Validate migration correctness assumptions

### 4. Verify whether `exists?(..., type: :cas)` must honor legacy-bucket fallback

File:
- `cache/lib/cache/s3.ex`

Problem:
The new migration logic checks the legacy bucket for some read paths, but `exists?/2` with `type: :cas` only checks the primary CAS bucket. During migration, an object that still exists only in the shared bucket can therefore look absent.

Action:
- Audit all callers of `exists?(..., type: :cas)`.
- Decide whether the migration contract requires fallback behavior there too.
- If yes, align `exists?/2` with presign and download behavior.
- If no, document why those callers remain correct without fallback.

Why this matters:
The code may already be correct if no caller depends on migration completeness here, but that assumption should be explicit rather than accidental.

Definition of done:
- Either `exists?/2` supports migration fallback, or its current behavior is confirmed safe and documented.

### 5. Decide whether `KeyValueRepo` needs periodic vacuum outside size-based eviction

File:
- `cache/lib/cache/sqlite_maintenance_worker.ex`

Problem:
`KeyValueRepo` uses incremental vacuum behavior, but the maintenance worker only vacuums `Cache.Repo`. The new KV database is only vacuumed during size-based eviction. On the common time-based path, deleted rows can accumulate freelist pages without periodic reclamation.

Action:
- Decide whether `KeyValueRepo` should be included in `SQLiteMaintenanceWorker`.
- If yes, add it there.
- If no, document why size-based vacuuming alone is sufficient for expected workload.

Why this matters:
Without a clear decision, database growth behavior depends on traffic shape and may drift over time.

Definition of done:
- There is an explicit strategy for vacuuming `KeyValueRepo`, implemented or documented.

### 6. Confirm the 30-second read contention ceiling is acceptable

File:
- `cache/lib/cache/key_value_store.ex:96`

Problem:
KV reads can block up to the configured SQLite `busy_timeout` before returning `{:error, :not_found}` under contention. The default is 30 seconds. That may be an intentional trade-off, but it is high for a GET path.

Action:
- Review expected latency SLOs for KV reads.
- Decide whether this path should:
  - keep the 30-second wait,
  - use a shorter timeout for read-through lookups, or
  - use separate behavior for reads vs maintenance work.
- Update code and tests if the current default is too slow.

Why this matters:
This is a product behavior decision disguised as a database setting.

Definition of done:
- The timeout reflects an intentional latency policy, not an inherited default.

### 7. Verify metric naming and units for eviction duration

File:
- `cache/lib/cache/key_value/prom_ex_plugin.ex:88`

Problem:
The metric name says `seconds`, while the code records `duration_ms` with millisecond units. This may already normalize correctly, but the naming and measurement are easy to misread.

Action:
- Inspect the emitted Prometheus metric and Grafana panels.
- Make the name, unit, and dashboard expectation consistent.

Why this matters:
Telemetry should be trustworthy during rollout of a large storage change.

Definition of done:
- The metric name, emitted unit, and dashboard interpretation all agree.

## Priority 3: Reduce maintenance and performance drag

### 8. Extract duplicated SQLite helper logic

Files:
- `cache/lib/cache/key_value_entries.ex`
- `cache/lib/cache/key_value_eviction_worker.ex`
- `cache/lib/cache/key_value_store.ex`
- `cache/lib/cache/key_value/prom_ex_plugin.ex`

Problem:
Helpers like `busy_error?/1`, `set_busy_timeout!/1`, `remaining_time/1`, `file_size/1`, and `db_path/0` are duplicated across four modules.

Action:
- Move shared SQLite utility logic into a dedicated helper module, for example `Cache.SQLiteHelpers`.
- Update callers to use the shared implementation.

Why this matters:
It lowers the risk that future SQLite behavior changes get fixed in one place but missed in others.

Definition of done:
- Common SQLite helpers live in one place and duplicated copies are removed.

### 9. Simplify grouped-hash merging in the eviction worker

File:
- `cache/lib/cache/key_value_eviction_worker.ex:319`

Problem:
The worker merges grouped hashes with list concatenation, `Enum.uniq()`, and sorting, while related code already uses `MapSet.union/2`. The current path is less consistent and appears to redo deduplication that has already happened.

Action:
- Rework the merge path to use the same set-based approach as the other KV helpers.
- Keep sorting only where deterministic output is actually required.

Why this matters:
This is a smaller issue, but it reduces unnecessary work and makes the eviction pipeline easier to reason about.

Definition of done:
- Grouped hash merging follows one consistent set-based strategy.

### 10. Revisit `with_repo_busy_timeout` in `key_value_store.ex`

File:
- `cache/lib/cache/key_value_store.ex:118`

Problem:
The helper appears to set `busy_timeout` to the configured default and then restore the same value, so the PRAGMA updates may add overhead without changing actual timeout behavior.

Action:
- Confirm whether the helper is only needed for `checkout` / connection pinning.
- If so, remove the redundant timeout set-and-restore behavior.

Why this matters:
It keeps the hot read path simpler and avoids unnecessary SQLite PRAGMA churn.

Definition of done:
- The helper either changes behavior intentionally or is simplified to only the behavior that matters.

### 11. Remove redundant and obsolete indexes / migrations where appropriate

Files:
- `cache/priv/key_value_repo/migrations/20260309190000_create_key_value_entries.exs`
- `cache/priv/repo/migrations/20260306120000_add_last_accessed_at_id_index_to_key_value_entries.exs`

Problem:
The new KV repo migration creates both a single-column `last_accessed_at` index and a composite `(last_accessed_at, id)` index, even though the composite index already covers the leading column. Separately, the old repo gets a migration for a table that is no longer used after the split.

Action:
- Confirm the single-column index is not needed.
- Decide whether the old-repo migration should remain for rollout compatibility or be dropped before merge.

Why this matters:
These are minor issues individually, but they add avoidable index and migration weight.

Definition of done:
- Only necessary indexes and migrations remain.

### 12. Fix minor telemetry / dashboard mismatches

Files:
- `cache/lib/cache/key_value_eviction_worker.ex:63`
- `cache/priv/grafana_dashboards/cache_service.json:1932`

Problem:
The worker can report `:size` as the trigger before it has actually determined the trigger, and the Grafana threshold is slightly off from the code's hysteresis release target.

Action:
- Correct the trigger labeling if the distinction matters operationally.
- Align the Grafana threshold with the configured 23 GiB release target.

Why this matters:
These are cosmetic issues, but storage rollouts benefit from dashboards and telemetry that reflect reality exactly.

Definition of done:
- Trigger metadata and Grafana thresholds match actual runtime behavior.

## Priority 4: Document temporary migration costs and edge behavior

### 13. Document extra S3 round-trips during fallback reads

Files:
- `cache/lib/cache/s3.ex:65`
- `cache/lib/cache/s3.ex:289`
- `cache/lib/cache/clean_project_worker.ex`

Problem:
Migration-mode fallback adds extra HEAD requests before presign and download, which increases CAS read latency temporarily. Also, delete flows intentionally do not fully clean the legacy bucket, and when both bucket env vars point to the same bucket some cleanup work is duplicated.

Action:
- Document these behaviors in the PR description or rollout notes.
- Call out that they are temporary migration trade-offs, not the long-term target architecture.

Why this matters:
This prevents reviewers and operators from treating transitional behavior as permanent technical debt.

Definition of done:
- The migration-specific latency and cleanup trade-offs are explicitly documented.

### 14. Make fragile tests less order-dependent where practical

Problem:
Some eviction tests avoid unstubbed PRAGMAs only because `max_duration_ms: 0` stops execution early. Those tests may break if internal execution order changes.

Action:
- Harden the most fragile tests by stubbing the full expected SQLite interaction, or by narrowing the assertion target so the test does not depend on unrelated execution order.

Why this matters:
The current test suite is broad and valuable; reducing order sensitivity will make it more resilient as the implementation evolves.

Definition of done:
- Tests no longer depend on incidental deadline short-circuiting for correctness.

## Recommended execution order

1. Fix the CAS fallback error classification bug.
2. Remove non-source artifacts (`changes.md`, tracked SQLite files).
3. Audit migration correctness assumptions around `exists?/2`.
4. Decide operational policy for `KeyValueRepo` vacuuming and read contention timeout.
5. Align telemetry units and dashboard thresholds.
6. Do the lower-risk cleanup refactors (shared SQLite helpers, merge simplification, redundant index review, helper simplification).
7. Add rollout notes for temporary migration behavior.
8. Harden fragile tests after behavior is settled.

## What is already strong

- The KV repo split is conceptually sound and avoids dangerous data migration work.
- The cursor-based eviction design is strong, especially the null-first ordering and composite-index-friendly batching.
- The verify-and-delete transaction closes an important race during eviction.
- The size-based eviction loop is well bounded through deadlines, hysteresis, and Oban uniqueness.
- Test coverage is broad across contention handling, CAS fallback, repo splitting, and eviction flow.
