# Grafana fixtures

## Dashboard query contracts

`dashboard-queries.json` is a read-only snapshot of panel query expressions from
Tuist's nine provisioned dashboards. It contains 301 PromQL contracts, one Loki
selector and one TraceQL selector. Only expressions, datasource references,
query type and source basename are exported; no credentials, webhook settings,
Grafana tokens or complete dashboards are included.

Regenerate from an explicitly supplied dashboard checkout:

```sh
mix run --no-start scripts/grafana_inventory.exs /path/to/grafana-dashboards test/fixtures/grafana/dashboard-queries.json
```

Unlike the normalized PromQL fixture, this snapshot preserves dashboard variables
and TraceQL hints. Parser acceptance with representative variable substitutions
is a grammar regression test, not independent numerical conformance or proof of
live Grafana datasource compatibility. Live-only queries, dashboard variables,
recording rules and alert rules must be inventoried separately.

## Tuist Grafana query corpus

`tuist-corpus.json` holds every distinct PromQL and LogQL query from Tuist's
Grafana Cloud stack, copied verbatim on 2026-11-05 through the Grafana MCP. It
covers 31 non-deprecated dashboards that have PromQL/LogQL panels and all 170
alert rules, including the definitions of the four `kura:*` recording rules.
In total that is 1,178 queries: 1,112 PromQL and 66 LogQL. SQL and TraceQL
queries are excluded. No query contained credentials, so nothing is
anonymized. Each query records its language, whether panels run it as a range
query (`r`), an instant query (`i`) or both, and the dashboards and alerts that
use it. `variables` stores the dashboard variable values used at test time.
These use the canary environment (cluster `tuist-canary`, env `canary`,
namespace `tuist-canary`), the first option of each other variable, and All
where a dashboard defaults to All.

`Pulse.Test.GrafanaCorpus` (test/support/grafana_corpus.ex) interpolates
variables and macros the way Grafana does and builds the synthetic data.
`$__rate_interval` is max(step + scrape, 4 × scrape) with a 60 s scrape
interval, and `$__interval` is the 300 s step. Range queries cover the hour
ending at 1759996800 (2025-10-09T08:00:00Z). The synthetic series are derived
from each query's selectors: two entities share topology labels so joins
match, histograms get bucket families, and counters include resets. The log
lines follow the formats the queries parse: logfmt, JSON, regexp and pattern.

`tuist-corpus-reference.json` holds the answers Prometheus 3.5.0 and Loki 3.7.9
return over the same data. Loki runs with `discover_service_name: []` and
`discover_log_levels: false`, so its stream labels are exactly the pushed ones.
The file stores the corpus SHA-256, and the test fails when the corpus changes.
To regenerate it:

```sh
MIX_ENV=test mix run --no-start scripts/tuist_corpus_reference.exs \
  --prometheus /path/to/prometheus-3.5.0.linux-amd64 \
  --loki /path/to/loki-3.7.9-linux-amd64
```

Results are stored sorted by label set, so regenerating the file over the same
inputs is byte-stable. The test compares results as sets.
`test/pulse_web/controllers/grafana_corpus_test.exs` evaluates every query
through Pulse's HTTP APIs on the S3 adapter and requires each answer to equal
the reference answer. When both backends reject a query, that also counts as
equal; this happens for one query on synthetic data, where a join yields
duplicate series. Log-stream results ignore the `service` and
`detected_level` labels that Pulse copies from the pushed `service_name` and
`level` labels (see docs/protocol-coverage.md).

## Datasource HTTP request contracts

Dashboard queries do not cover Grafana's surrounding discovery and transport
requests. The HTTP controller tests additionally preserve these client shapes,
inspected on 2026-11-05:

| Pinned source | Contract replay |
| --- | --- |
| [Prometheus datasource `3bfc304`, `resource_clients.test.ts:101–135`](https://github.com/grafana/grafana-prometheus-datasource/blob/3bfc304ade246040662915c46662c3d4352690b3/packages/grafana-prometheus/src/resource_clients.test.ts#L101-L135) | Label dictionaries with the default `limit=40000`, including `U__http_2e_status:sum` for `http.status:sum`. |
| [Same revision, `utf8_support.test.ts:12–36`](https://github.com/grafana/grafana-prometheus-datasource/blob/3bfc304ade246040662915c46662c3d4352690b3/packages/grafana-prometheus/src/utf8_support.test.ts#L12-L36) | Seven original encoded names, including doubled underscores, Chinese text and an emoji, through authenticated tenant-scoped GET/form POST discovery. The separately authored mixed space/underscore/dot case is a local control. |
| [Prometheus common `v0.73.1`, `TestValueUnescapeErrors`](https://github.com/prometheus/common/blob/v0.73.1/model/metric_test.go#L574-L636) | All nine nonempty input/output rows; the empty name has no HTTP path segment and is not counted. Malformed escapes preserve the whole original name, including surrogate rejection. Additional controls cover decoded 256/257-byte boundaries, one decoding pass and the pinned five-hex-digit ceiling. |
| [Prometheus `v3.5.0` (`8be3a956`), `TestEndpoints` result-limit rows](https://github.com/prometheus/prometheus/blob/8be3a9560fbdd18a94dedec4b747c35178177202/web/api/v1/api_test.go#L1146-L1464) | The original two-series expression, 0..2 inclusive range and values 42/3.1415; limits 0/1/2 retain full samples and exact truncation warnings. Additional controls cover empty/oversized limits, sorted instant vectors, unchanged scalar/string results and safety failures despite `limit=1`. These are API-table ports, not additional Mimir deployment scenarios. |
| [Prometheus datasource `3bfc304`, `custom_query_params_test.go:179–243`](https://github.com/grafana/grafana-prometheus-datasource/blob/3bfc304ade246040662915c46662c3d4352690b3/pkg/promlib/middleware/custom_query_params_test.go#L179-L243) | Optional `stats=all` on GET and form POST instant/range queries. Pulse returns ordinary truthful results without fabricated JSON statistics, matching [Mimir's renderer policy](https://github.com/grafana/mimir/blob/54720776b661e67dd6e90cf033793076686741bc/pkg/querier/stats_renderer.go#L13-L21). |
| [Loki datasource `280bf26`, `logs_volume.go:237–256`](https://github.com/grafana/grafana-loki-datasource/blob/280bf268a25b1577b620568b34c0f8d721b25255/pkg/loki/logs_volume.go#L237-L256) and [`healthcheck.go`](https://github.com/grafana/grafana-loki-datasource/blob/280bf268a25b1577b620568b34c0f8d721b25255/pkg/loki/healthcheck.go) | Actual `vector(1)+vector(1)` health query and generated count-range shape with `offset 1ns`/millisecond steps. Authored asymmetric boundary data proves counts 3 then 1, not merely successful parsing. This is a client-callsite control inside the HTTP/native-Parquet/S3 Loki harness, not a new upstream Loki scenario. |

`mimir_service_conformance_test.exs` retains the original Mimir integration
inputs/oracles and adds separately labelled RW1/RW2 UTF-8 discovery controls
through native Parquet/S3 with Grafana's escaped path and default limit.
The complete-store work and dictionary budgets apply before explicit HTTP
truncation; MCP discovery remains complete-or-error.

The surrounding [Mimir](../promql/mimir/services/README.md),
[Loki](../logs/loki-upstream/README.md) and
[Tempo](../traces/tempo_integration/README.md) ledgers distinguish original
upstream cases from adaptations and local controls. These tests exercise Pulse,
not a running Grafana Cloud instance or the complete upstream deployment suites.
Passing them does not establish full language parity, production capacity,
notification delivery or historical data migration. Optional datasource-managed
ruler/Alertmanager APIs remain distinct from Grafana-managed alert queries.

The adapted Prometheus API/common table rows retain their Apache-2.0 notices;
the license text is retained in [LICENSE-Prometheus](../promql/mimir/LICENSE-Prometheus)
and [Prometheus-common-LICENSE](../logs/loki-upstream/Prometheus-common-LICENSE).
The Mimir/Loki/Tempo ledgers retain their separate upstream test licenses.
