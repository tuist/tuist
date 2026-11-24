# Phase 0 replay inputs

The phase 0 replay runs the evaluator's metric statistics over six months of
production metrics, with thresholds frozen before it runs, and scores the result
against IRM incidents left out of tuning. This file says how the inputs are
fetched so the replay can be reproduced. The data itself is not in the
repository; it goes in `.amp/in/replay-data/` (or any directory you pass).

## Files

| File | Content |
| --- | --- |
| `manifest.json` | One entry per entity: `key`, `phenomenon`, `role` (numerator, denominator, backlog, backlog_age, resource), `promql`, optional `split` (label and value picked from a grouped query), `units`, `datasource`, `coverage_probe` (observed before fetching) and `coverage_fetched` (written by the fetch) |
| `<key>.csv` | `timestamp,value`; Unix seconds aligned to 300 s, value as Prometheus returns it. Windows with no data have no row: treat them as *unknown*, never as zero |
| `incidents.json` | All Grafana IRM incidents with start, end, creation and close times, plus an `independence_group` for duplicates |
| `fetch.py` | Fetches every entity in the manifest and writes the CSVs |

## Source

- Datasource: `grafanacloud-prom` (Grafana Cloud Mimir, the stack's default
  Prometheus, `https://tuist.grafana.net`). The Pulse and Fly datasources are not
  used.
- Range: 183 days, `2026-05-17T00:00:00Z` to `2026-11-16T00:00:00Z`
  (exclusive). Step: 300 s. Queries run in 36-day chunks (10,368 points, under
  Mimir's 11,000 points per series).
- Counters use `increase(...[5m])` at a 5-minute step, so each row counts the
  window that ends at its timestamp. The values are extrapolated and are not
  exact integers.
- 5xx series are written as `numerator or (0 * denominator)`, so a window that
  has traffic but no 5xx is 0 rather than missing.

## Fetching

```sh
GRAFANA_TOKEN=<Grafana service account token with Viewer> \
  python3 -I .amp/in/replay-data/fetch.py .amp/in/replay-data
```

The script calls
`/api/datasources/proxy/uid/grafanacloud-prom/api/v1/query_range` for each
distinct PromQL (24 queries, 6 chunks each), splits the grouped results into
entities and records `coverage_fetched` in the manifest. It only reads.

The Atlas Grafana tools (`grafana__query_prometheus`) run the same queries.
They suit spot checks, but their results come back only as tool output, which
is too small for the roughly 50,000 points each entity has.

Incidents come from `gcx irm incidents list --from 2025-01-01T00:00:00Z --to
<now> -o json`, through Atlas `grafana__run_gcx_command`.

## Label caveats

Check labels before you add an entity:

- Adaptive Metrics aggregates `instance` and `pod` away on `tuist_oban_*`,
  `tuist_runners_*`, `tuist_clickhouse_*` and the Phoenix metrics, and removed
  Phoenix's `route`. Every query must aggregate (`max by (queue)` and similar).
  Raw selectors return 422.
- `cache_nginx_http_responses_total` has no `env` label. Production is selected
  with `instance!~".*-(canary|staging)"`.
- Kura metrics have no region label. Region is joined from `kura_node_info`, with
  `topk by (namespace, pod) (1, ...)` because some pods carried two regions.
  Internal, health and metrics routes are excluded.

## Coverage limits that shape the replay

- Server ingress (`tuist.dev`, `registry.tuist.dev`) starts 2026-08-29, apart
  from a day on 2026-07-28. The Phoenix fallback covers only 2026-05-17 to
  06-18 and 10-31 onwards. There is no server request data from 2026-06-18 to
  2026-08-29.
- Kura cache ingress starts 2026-09-15. The legacy `cache-nginx` fleet covers
  all 183 days.
- Oban oldest-job age starts 2026-08-14. Before 2026-08-16, `process_xcresult`
  backlog is intermittent (8 of 91 days are complete).
- Kura regions changed: `eu-central` and `scw-fr-par-runners` were retired, and
  the other regions besides `us-east` and `us-west` appeared from 2026-09-09.
- Runner fleets were renamed often. Use the `all`, `linux` and `macos` totals;
  they are complete from 2026-08-16.
- ClickHouse metrics start in September or October. `pgbouncer_maxwait` is
  intermittent.

Before freezing thresholds, map each incident to the entities that had data
during it. Several early incidents (1 to 8) have no ingress coverage.
