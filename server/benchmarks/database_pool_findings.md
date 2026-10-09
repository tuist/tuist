# Database pool investigation and local validation

## Scope

This change adds physical-repository attribution and a partial index for closed runner-session lookups. It does not change pool sizes, queue settings, flush scheduling, or ClickHouse query limits, and it is not a demonstrated fix for ClickHouse write starvation.

Production inspection used bounded read-only tools. No production writes, migrations, extension installations, maintenance, deployments, or pool-size changes were performed. All fixture writes and index builds described here ran locally. Production identifiers, database roles, table volumes, and incident measurements do not belong in this public benchmark document.

## Investigation method and attribution limits

- Compare workload-aggregated pool starvation samples, queue-time histograms, and checkout failures over the same time window. A starvation-sample ratio is not a percentage of queries that failed.
- Keep primary and replica database probes separate. Establish which endpoint a tool reaches before comparing plans, counters, or activity.
- Distinguish Cloud ClickHouse traffic from shadow reads and writes. Dynamic read routing emits the physical shadow repository's telemetry prefix, not the logical read repository's prefix.
- Do not infer query frequency from cumulative table-scan totals. Parallel scan workers can also inflate scan counters.
- Query-log execution time can indicate connection-hold contributors, but includes driver/network effects and does not establish inefficient SQL or temporal causation.
- Missing statement statistics, aggregated instance labels, or unavailable activity/wait details limit attribution. More observability is preferable to speculative pool increases.

For example, compare a ten-minute starvation ratio over a consistently sampled seven-day window:

```promql
max_over_time((
  100 * sum by (cluster, workload, repo) (
    rate(tuist_repo_pool_checkout_queue_starved_samples[10m])
  ) / sum by (cluster, workload, repo) (
    rate(tuist_repo_pool_checkout_queue_total_samples[10m])
  )
)[7d:10m])
```

Filter to the intended environment before drawing conclusions. Histogram estimates and sampling are not precise request-level maxima; coarser long-window samples are not directly comparable.

## Monitoring changes

All six physical pools and query-event prefixes are covered, preserving separate Cloud, shadow, and ops labels. Optional pools emit nothing when absent. Both shadow repos have Ecto tracing; detailed ClickHouse read-outcome metrics cover shadow reads too. Both read prefixes forward into one sanitized internal event before export, avoiding duplicate Prometheus metric families. The ops label matches the existing transport listener: `ops_clickhouse_read`.

Existing ClickHouse read-failure and p90-latency alerts aggregate Cloud and shadow reads. Newly visible shadow failures or latency may make them fire without threshold changes. The repos do not have identical timeout settings: Cloud configures a server-side execution limit, while shadow reads do not. A shadow client timeout does not prove the server-side query stopped. See `infra/helm/k8s-monitoring/alerts.md` for the per-repo distinction.

`idle_time` measures time idle **before checkout**, not occupancy and not an extra component of total query time. Missing phases remain absent rather than becoming zero. Decode time is not connection occupancy. Transaction checkout waiting can occur on `begin`, while time holding a connection between statements remains unmeasured. The idle-time panel does not resolve these distinctions by itself. Its histogram buckets end at 30 seconds, so quantiles for quiet pools are uninformative even though sum/count averages remain valid.

## Candidate decisions

### Closed runner-session lookup: retain

`RunnerSessions.latest_for_pod/1` first looks for an open session, then falls back to the most recent closed session. The existing pod-name index covers open sessions only, so the fallback can perform a full-table scan.

The concurrent partial `(pod_name, started_at)` index with `ended_at IS NOT NULL` targets this fallback without rewriting the open-first semantics or duplicating the open index. No index has been applied to production and there is no production before/after improvement measurement.

Do not narrow the predicate to nonempty pod names: a generic prepared plan cannot establish that an unknown parameter is nonempty. The local benchmark uses Ecto's `NOT (ended_at IS NULL)` spelling, repeated named prepared statements, and explicitly forced generic plans; the candidate retains index usage.

### Device-code lookup: defer

Although `device_codes.code` has no index, interval snapshots did not demonstrate active lookup traffic beyond the bounded probe. A missing index and large lifetime scan totals alone do not justify attributing current pressure to that path.

### Oban metrics polling: reject tested rewrite

Changing to `count(*)` did not materially improve the grouped jobs-count query. Splitting completed/non-completed groups with `UNION ALL` doubled scanned buffers and performed worse, so that rewrite was rejected. Existing index size and maintenance should be investigated before adding overlapping indexes. No Oban query, index, vacuum, or maintenance change was made.

## Reproducing local validation

Local measurements used PostgreSQL 16.13/Homebrew on Apple Silicon and ClickHouse 26.1.2.11.

From the repository root:

```sh
psql -X -h /tmp -d postgres -v ON_ERROR_STOP=1 \
  -f server/benchmarks/closed_runner_session_index.sql
```

Use an empty, disposable local database. The SQL script refuses TCP connections and recovery/replicated databases, and additionally checks for an application table in the **connected database**. That table check cannot identify an application stored in another database on the same server; these guards are not a general environment-identity guarantee.

The fixture seeds 150,000 synthetic rows with three rows per pod, 0.1% open rows, and two existing secondary indexes, alternates candidate order, then rolls everything back. Real deployments have more secondary indexes and different row/pod sizes: these are local comparisons, not production cost forecasts.

Three complete runs produced:

| Operation | Baseline median | Indexed median | Samples |
| --- | ---: | ---: | --- |
| Missing/existing closed-pod read | 9.071 ms | 0.016 ms | 42 baseline; 48 indexed, including 6 forced-generic reads |
| Open inserts, 1,000-row batch | 8.586 ms | 8.279 ms | 15 batches each |
| Session closes, 1,000-row batch | 5.402 ms | 8.305 ms | 15 batches each |

Close-batch median WAL increased from 661,388 to 754,764 bytes, approximately 93 additional bytes per synthetic close. Open-batch WAL was identical at 652,176 bytes. Open sessions have no entries in the added index, but still require predicate evaluation; similar open timings do not establish zero overhead. The added index was 6,176 kB. Read buffers dropped from thousands to 3–4.

Timing noise was substantial: baseline open batches ranged from 4.769 to 57.642 ms and closes from 2.663 to 26.718 ms. A repeat initially hit the shared local server's connection limit; no unrelated sessions were terminated, and subsequent runs succeeded. Prefer repeatable plan and WAL evidence over small timing differences. The batched write test excludes commit latency, network round trips, and application pool contention; single-row closes differ. Later updates to already-closed sessions also maintain the index and are not measured by this fixture.

From `server/`, with dependencies compiled:

```sh
mise exec -- elixir -pa '_build/test/lib/*/ebin' benchmarks/check_closed_session_index.exs
mise exec -- elixir -pa '_build/test/lib/*/ebin' benchmarks/repo_metrics.exs
```

The migration check runs the actual concurrent Ecto migration and rollback on 150,000 synthetic rows in a disposable local schema. It verifies `indisvalid`, `indisready`, key columns, predicate, and index removal. Measured runs took 304–341 ms up and 4–5 ms down, including migrator bookkeeping; these are not production build-time estimates.

The isolated monitoring harness passed 17 focused tests covering physical labels, actual local dynamic-repo telemetry, timeout classification, optional-pool absence, absent timing phases, single-family export, and rejection of ops/shadow-write events. It preserves the normal test compile-time dynamic-repo default but supplies local connection settings and explicitly attaches forwarders, so it **does not prove application startup wiring or replace normal `mix test`/CI**.

Before merging, run the normal application lifecycle and formatter from `server/`:

```sh
mix test test/tuist/repo/prom_ex_plugin_test.exs test/tuist/clickhouse_repo/prom_ex_plugin_test.exs
mix format --check-formatted
```

Also validate dashboard JSON, unique panel IDs, grid positions, and `git diff --check`. An isolated harness pass must not be reported as a normal application or CI pass.

## Rollout follow-up

1. After an independently authorized deployment, verify the closed-session index is valid/ready on the primary and replica, and a bounded fallback plan selects it. Track interval index usage and table scan deltas; do not reset statistics.
2. Interrupted concurrent builds can leave an invalid index that blocks every subsequent migration/deployment retry until an operator recovers it. The migration comment and `server/priv/AGENTS.md` describe manual, explicitly authorized recovery after verifying no build is active. Do not use `create_if_not_exists` to hide an invalid index.
3. Correlate new shadow series and spans with queueing, execution time, checkout failures, and actual routed queries during the same pressure windows. Mirrored-write tasks may lack propagated trace context and appear as separate roots.
4. Distinguish insert latency, request/worker-driven flushes, arrival bursts, network/PgBouncer effects, and between-statement holds before increasing pools or rewriting SQL. Statement-level observability, shadow server-side query limits, and index maintenance are separate operational decisions, not changes performed by this investigation.
