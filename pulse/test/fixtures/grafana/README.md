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
