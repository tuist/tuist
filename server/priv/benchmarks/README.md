# Build-entity volume gates

These benchmarks exercise the real domain methods, not approximations of their SQL. They create synthetic data only, refuse non-loopback hosts and database names outside `build_entities_bench_*`, never append to an existing dataset unless explicitly reusing it, and never reset a shared cache or run against production.

Run from `server/` with installed Mise tools and local PostgreSQL available for the Once gate:

```bash
# Seven kinds: 7.77 million inserted observations, 70,000 identities,
# 100,000 hot-entity observations per kind, replay/NULL corrections.
# Spread over 85 days/four insertion months (Xcode modules: 29 days).
bash priv/benchmarks/run_build_entities.sh

# Five native ClickHouse parent families: 11 million inserted rows,
# 100-ID recent, middle, scattered and wrong-project lookups.
BUILD_ENTITY_BENCH_MODE=parents bash priv/benchmarks/run_build_entities.sh

# Actual PostgreSQL migrations, 5,005,000 actions, 10,001 runs,
# 105,000 mappings in each mapping table, real recovery/observation writes.
BUILD_ENTITY_BENCH_MODE=once bash priv/benchmarks/run_build_entities.sh

# Higher inventory cardinality: 100,000 identities, 1.11 million inserts.
BUILD_ENTITY_BENCH_KINDS=xcode/cache_action \
BUILD_ENTITY_BENCH_ENTITIES=100000 BUILD_ENTITY_BENCH_OBSERVATIONS=10 \
bash priv/benchmarks/run_build_entities.sh
```

The wrapper starts a private loopback ClickHouse on port 18233 (override `BUILD_ENTITY_BENCH_PORT` if occupied), enables `system.query_log`, limits its server memory to 8 GiB, and terminates only its own verified process. It refuses an already occupied port. The HTTP port is passed **after** `mise exec -- env` so development hooks cannot reset it. All three harnesses require `BUILD_ENTITY_BENCH_EXPECTED_PORT`, reject shared port 8123 and verify read/write repo ports before writes; JSON records the actual port. Its configuration, datasets and logs remain in the printed temporary directory. The Once mode also retains its uniquely named PostgreSQL database. Nothing starts the application, Oban workers or the preview, and no unrelated database is dropped. Remove retained datasets only after inspecting the results and verifying their names.

## Measurements and gates

[build_entities_results.json](build_entities_results.json) retains reduced shipping-gate evidence (fixture sizes, sample counts/percentiles and server scan/memory summaries), without raw SQL or customer data. Full per-query artifacts are named in it; rerun these commands for a new environment or query/storage change.

The entity gate covers 112 scenarios across seven kinds: inventory/counts, environment/branch membership, filtered name search, one-day and full-retention windows, name search/sorting, deep numbered pages, get, newest-first history/cursors, activity filters, duration sorting, current/previous/daily analytics, duration scatter and the Overview get/history/analytics fan-out. Native parent hydration is measured separately, including tenant rejection and latest nullable corrections. Once measures the actual mapped-slot join, 100-parent context, indexed first recovery page and a complete repeated recovery sweep with synchronous observation writes and a duplicate-insensitive count assertion.

The entity/native-parent default is 20 serial samples and 80 samples at concurrency four per scenario. The default sample-p95 gate is 2,000 ms (`BUILD_ENTITY_BENCH_P95_MS`). Once also uses 20 serial/80 concurrent samples by default (`BUILD_ENTITY_ONCE_ITERATIONS`), a 1,000 ms context/join gate and a 60-second complete-sweep gate. JSON records sample counts; these are local workload percentiles, **not production p95/p99 or controlled cold-cache results**. Overview fan-out includes domain work, not browser/network/authentication time. REST/MCP/LiveView regression tests establish that those surfaces call these shared paths; they are not HTTP load benchmarks.

The entity JSON includes every captured SQL duration, read rows/bytes and peak memory, plus ClickHouse version. The parent JSON adds selected parts/marks/ranges, projections and `EXPLAIN indexes` plans. Once includes `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` from the actual executed queries, sweep time and PostgreSQL query count. Missing query logs or mismatched fixture cardinalities fail the run instead of silently producing a performance claim. `<output>.jsonl` preserves incremental entity measurements if a later gate fails.

Useful overrides:

| Variable | Meaning |
| --- | --- |
| `BUILD_ENTITY_BENCH_OUTPUT` | JSON destination; default inside the retained instance directory |
| `BUILD_ENTITY_BENCH_ENTITIES` / `BUILD_ENTITY_BENCH_OBSERVATIONS` / `BUILD_ENTITY_BENCH_HOT` | Identities per kind, observations per identity, additional hot observations |
| `BUILD_ENTITY_BENCH_KINDS` | Comma-separated selections, e.g. `gradle/task,xcode/cache_action` |
| `BUILD_ENTITY_BENCH_OPERATIONS` | Comma-separated entity operation names for targeted comparisons |
| `BUILD_ENTITY_BENCH_ITERATIONS` / `BUILD_ENTITY_BENCH_CONCURRENCY` | Repetitions and concurrent callers |
| `BUILD_ENTITY_BENCH_NATIVE_ROWS` / `BUILD_ENTITY_BENCH_NATIVE_PROJECTS` | Native rows per project/family and project count (at least two) |
| `BUILD_ENTITY_BENCH_NATIVE_PARENTS=1` | Include native parent workloads in the entity run |
| `BUILD_ENTITY_BENCH_SCHEMA_REFERENCE` | Fully migrated local reference database on the same server; verify native keys, types and skip-index definitions |
| `BUILD_ENTITY_ONCE_RUNS` / `BUILD_ENTITY_ONCE_ACTIONS` / `BUILD_ENTITY_ONCE_RECENT` / `BUILD_ENTITY_ONCE_HOT` | Once background runs, actions per run, recent terminal runs and hot-run actions |

For repeated query-shape experiments on an already running **private** ClickHouse, invoke the Elixir harness directly with `BUILD_ENTITY_BENCH_DATABASE=<retained-name>`, `BUILD_ENTITY_BENCH_REUSE=1`, the same workload cardinalities, and both `TUIST_SERVER_CLICKHOUSE_HTTP_PORT=<private-port>` and `BUILD_ENTITY_BENCH_EXPECTED_PORT=<private-port>` after `mise exec -- env`. Reuse does not seed or mutate observations. The wrapper intentionally creates a fresh instance, so it is not the reuse entry point.

## Verified optimization evidence

On the same 7.77-million-insert private dataset, alternating the old and optimized domain implementations (20 serial/80 concurrency-four calls each) returned identical maps on every pair. Filtered inventory concurrent sample p95 improved **2.3–4.0×** across the seven kinds. This paired test avoids claiming a speedup from different cache/merge states alone.

The final private-instance gate passed all 112 scenarios; worst concurrency-four sample p95 was **769 ms** for full-retention filtered inventory (all identities eligible). The 100,000-identity gate passed all 16 scenarios, worst p95 **619 ms**, peak query memory **72.83 MiB**. These are synthetic domain workloads, not production HTTP measurements.

Earlier `*-shipping-monthly.json` results used isolated databases but accidentally reached the shared 8123 process because Mise reset an exported port. They are **not private-instance sign-off**. Reduced evidence now points to endpoint-verified results. The original five-million-action Once run and native-parent run were direct private-port runs; the new wrapper was separately revalidated with 505,000 actions and the same 105,000 mappings/sweep observations. A new five-million-action seed hit its bounded 300-second seeding timeout on the busy host; it is not a completed gate or a read-path latency result.

## Latest-row safety

The undeployed observation migration orders by `(project_id, system, kind, entity_id, id)` and versions by `inserted_at`. Observed time is deliberately not a replacement key. Domain `FINAL` reads pin cross-partition replacement and disable pre-FINAL non-key PREWHERE/skip-index filtering. Explicit PREWHERE contains only replacement-key scope/identity columns. Filtered inventories count matching latest observations once and join the catalog; catalog time/search candidates are a safe superset and narrow the read without hiding corrections. Time/cohort filters run after replacement. Do not prune insertion-month partitions from observed time or replace missing values with earlier versions.

An old prototype database may already have applied the same migration filename with `observed_at` in the key. It is **not compatible** with the new reader. Use a fresh isolated database for validation; recreate only your own disposable prototype feature tables before restarting a preview. Do not reset shared databases or attempt this change on deployed customer tables. Production table absence was verified read-only before selecting this migration strategy.
