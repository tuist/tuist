# Persistent build inventories

## Boundary
- `Tuist.BuildEntities` owns run-independent identities and bounded cross-run observation queries. Native facts remain authoritative for execution details.
- Supported resources: Gradle tasks, generated Xcode modules, declared Once action slots, Mix files and Mix modules. Xcode compilation-cache keys and Bazel digests are not stable logical identities and are deliberately excluded; preserve their native run/cache routes.
- Identities use a versioned length-prefixed encoding, deterministic project/system/kind UUIDs and deterministic observation IDs. Preserve identity field order and collision fixtures. Gradle includes root project/build/task paths and type; Xcode includes project/target; Once requires declared target/capability/index mappings; Mix uses reported paths or qualified module names.

## Rollout and writes
- `FeatureFlags.build_entities_enabled?/1` requires the project's `:build_entities` opt-in and an inactive `:build_entities_kill_switch`, in every environment. Check before producer mapping, Once mapping persistence and all new public surfaces. Native ingestion and legacy pages must continue while disabled. Tests opt in their own project with `FunWithFlags.enable(:build_entities, for_actor: project)`; never enable the flag globally in async tests.
- Batch observations through `Observation.Buffer`; never query or upsert the catalog during ingestion. A materialized view derives duplicate-insensitive identity/min/max/name states. Evaluate rollout flags once per distinct project in each batch.
- Once publication uses `record/2` with `sync: true`, a PostgreSQL run lock and `build_entities_published_at`. Mark only after ClickHouse acknowledges the whole run batch. Replayed completion and overlapping recovery sweeps skip published runs. A crash after the ClickHouse acknowledgment but before the PostgreSQL commit can still replay: deterministic IDs and replacement-safe reads remain required. See [../once_events/AGENTS.md](../once_events/AGENTS.md).
- Missing trustworthy identity skips derivation, not previously accepted reports. Retry invariance requires the same native parent/event identity; a newly minted build ID denotes a new execution.

## Replacement and query invariants
- Observations use `ReplacingMergeTree(inserted_at)` with stable `(project_id, system, kind, entity_id, id)` sorting, independent of mutable observed time. Insert-time partitions can contain versions of one observation in different months.
- Every observation read resolves the whole latest row with `FINAL` before time/cohort predicates, retaining NULL clears. `bounded_query/3` centrally adds non-overridable replacement settings: `do_not_merge_across_partitions_select_final: 0`, `optimize_move_to_prewhere_if_final: 0`, `use_skip_indexes_if_final: 0`.
- Explicit `PREWHERE` may select only whole replacement groups by project/system/kind/entity ID, never observed time, insertion partition or other mutable evidence. Catalog range/search candidates safely overapproximate matching entity IDs; exact membership/counts still use latest observations.
- Preserve bounded time windows, threads/memory/spill/deadline budgets, page sizes, 100-parent lookups and the 10,000-plus-one scatter bound. Query-limit failures are real errors, not empty facts or not-found responses.
- Inventory/history count-plus-page uses windows with an empty-page fallback; history totals precede cursor filtering. Filtered inventories join counts from one FINAL pass; unfiltered inventories keep catalog-only membership. Analytics combines period/daily aggregates with GROUPING SETS.

## Evidence and presentation
- Never invent timing, outcome, cache, environment or actor evidence. Cache writes are not misses, cache hits/skipped Gradle tasks have no execution duration, and zero measured values differ from unavailable metrics.
- Xcode modules report generated-project binary-cache outcomes, not compiler execution timing/status. Mix module duration is its containing file's measured compilation, shared with sibling modules and not additive across them.
- Parent context is optional metadata, fetched in one project-scoped native-parent batch and one recorded-user batch. Missing/deleted/org actors remain unknown, with no viewer/project-owner fallback. Latest native nullable fields use `argMax(tuple(value), version).1`; plain argMax would resurrect cleared values.
- Cover cross-month replacement, delayed writes and nullable corrections across every read path, query settings/FINAL regression, replay and publication failure/retry, flag-off native compatibility, tenant/toolchain isolation, exact filtered totals, stable cursors and truthful unknowns.
- Update `server/data-export.md` and English retention docs for stored fields/TTLs. Parent: [../AGENTS.md](../AGENTS.md).
