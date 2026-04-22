---
{
  "title": "Metrics",
  "titleTemplate": ":title | References | Tuist",
  "description": "Per-account Prometheus metrics exposed by Tuist at /api/accounts/:handle/metrics."
}
---
# Metrics reference {#metrics}

Tuist exposes a Prometheus-compatible scrape endpoint at
`GET /api/accounts/:handle/metrics` covering Xcode and Gradle builds,
test runs, binary cache events, and CLI invocations. The
[Grafana integration guide](/en/guides/integrations/grafana) walks
through installing the app plugin and wiring up the scrape.

## Endpoint {#contract}

- **Path:** `GET /api/accounts/:handle/metrics`
- **Auth:** `Authorization: Bearer tuist_<id>_<hash>` with the
  `account:metrics:read` scope on `:handle`.
- **Rate limit:** ~1 request per 10 seconds per account. Exceeding it
  returns `HTTP 429` with `Retry-After: 10`.
- **Formats:** OpenMetrics (`application/openmetrics-text; version=1.0.0`)
  when requested via `Accept`, otherwise Prometheus 0.0.4 text.

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
