---
{
  "title": "Metrics",
  "titleTemplate": ":title | References | Tuist",
  "description": "Per-account Prometheus metrics exposed by Tuist at /api/accounts/:handle/metrics."
}
---
# Metrics reference {#metrics}

Tuist exposes a Prometheus-compatible scrape endpoint at
`GET /api/accounts/:handle/metrics` that emits counter and histogram
samples describing what recently happened against the account: Xcode
builds, Gradle builds, test runs, test case outcomes, binary cache
events, and CLI invocations.

Scraping requires a bearer **account token carrying the
`account:metrics:read` scope** on the path's account. The full
installation walk-through — including the Grafana app plugin that
ships two dashboards out of the box — lives in the
[Grafana integration guide](/en/guides/integrations/grafana).

This page is generated automatically from the server's
`Tuist.Metrics.Schema` module, so it always matches the vocabulary the
scrape endpoint actually exposes.

## Endpoint contract {#contract}

- **Path:** `GET /api/accounts/:handle/metrics`
- **Auth:** `Authorization: Bearer tuist_<id>_<hash>` — a token that
  has the `account:metrics:read` scope on the `:handle` account.
- **Rate limit:** ~1 request per 10 seconds per account, with a
  small burst allowance. Breached requests get `HTTP 429
  Retry-After: 10`.
- **Content negotiation:** OpenMetrics text
  (`application/openmetrics-text; version=1.0.0`) when requested via
  `Accept`, otherwise the Prometheus 0.0.4 text format.
- **Semantics:** counters and histograms live in an in-memory ETS
  aggregator that resets on deployment. Prometheus' `rate()` and
  `increase()` handle resets correctly, so typical queries work
  without changes.

## Metric catalogue {#catalogue}

Metric names follow the `tuist_<namespace>_<subject>_<unit>` convention.
Counter names end in `_total`. Histogram family names end in `_seconds`,
and the scrape emits the usual `_bucket`, `_sum`, and `_count` sibling
series per family.

{{TUIST_METRICS_TABLE}}

## Cardinality notes {#cardinality}

The schema's label vocabularies are deliberately bounded:

- **No high-cardinality dimensions** — commit SHAs, branch names, and
  user identifiers are never used as labels.
- **Version labels included** where the dimension drifts slowly (two
  or three concurrent Xcode / Gradle / JVM versions in practice).
- **Shared bucket schedules** across duration histograms keep the
  series count predictable per project.

The aggregator is still bounded *per account* by how many unique
label combinations an account generates — large customers with many
schemes or modules can grow the ETS footprint proportionally. Keep
that in mind when provisioning Tuist self-hosted.
