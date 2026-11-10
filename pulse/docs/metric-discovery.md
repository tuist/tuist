# Metric label and series discovery

Pulse offers read-only, sample-backed metric discovery through MCP and a bounded
subset of the Prometheus HTTP metadata APIs. It uses the same tenant authorization
and query admission as other metric reads. No UI or Grafana rule execution is added.

## HTTP

| Endpoint | Result in `{"status":"success","data": ...}` |
| --- | --- |
| `GET /api/v1/labels` | Sorted distinct label names, including `__name__` when present |
| `GET /api/v1/label/<name>/values` | Sorted distinct values actually present for that label |
| `GET /api/v1/series` | Distinct label sets, ordered by label name/value pairs |

All three also accept `POST` with an **uncompressed**
`application/x-www-form-urlencoded` body. GET query strings and POST forms are
independently capped at 32 KiB. Oversized forms return 413, oversized query strings
414, and unsupported media types or compression 415. JSON and multipart forms are
not supported. Transport validation happens before authorization.

Use `X-Scope-OrgID` and the same bearer token as ingestion/querying. An omitted
tenant means `default`; an explicitly empty or repeated tenant header is invalid.
Never expose an unauthenticated production reader.

```sh
curl -G "$PULSE_URL/api/v1/label/host/values" \
  -H "Authorization: Bearer $PULSE_TOKEN" \
  -H 'X-Scope-OrgID: acme' \
  --data-urlencode 'match[]=requests_total{env="prod"}' \
  --data-urlencode 'start=1700000000' \
  --data-urlencode 'end=1700003600'
```

Supported parameters:

- Repeated `match[]` selectors are **ORed**. Matchers inside each selector are
  **ANDed**. Names/values may omit selectors; series requires at least one.
- Selectors accept metric names and the documented PromQL label matcher subset:
  `=`, `!=`, `=~`, `!~`. Regexes are fully anchored and missing labels match as
  empty strings. Every selector needs a matcher that does not match empty.
- `start` and `end` are optional inclusive Unix seconds (decimal/exponent) or
  RFC3339 timestamps with up to nine fractional digits. Pulse retains nanosecond
  precision within signed int64 nanoseconds; omitted bounds cover retained history.
- Optional `timeout` is seconds or a duration such as `500ms`, clamped to ten
  seconds and the server timeout. This is a query-work deadline, not a body-read
  deadline or preemption guarantee for native calls already running.
- Optional HTTP `limit` is a nonnegative signed-int64 integer. Omission, empty
  text and zero leave the result unlimited within server budgets. A positive
  limit returns the first entries in the normal result order and adds
  `warnings: ["results truncated due to limit"]` only when entries were omitted.
  It never bypasses scan, dictionary or result budgets: discovery completes
  before applying the requested response limit.

Label-value paths also accept Prometheus `U__` value-name escaping, including
hexadecimal Unicode code points and doubled underscores. For example,
`/api/v1/label/U__http_2e_status:sum/values` queries `http.status:sum`, not the
literal encoded name. Decoding follows Prometheus common v0.73.1: malformed
escapes preserve the entire original name, and decoding happens only once.
Its five-hex-digit escape ceiling is retained; six-digit escapes remain literal.
Decoded names still need valid UTF-8 and fit the normal 256-byte name budget.

At most 16 selectors, 64 total matchers, eight regexes, 1024 bytes per regex and
16 KiB total selector text/matcher name-value bytes are accepted. Matcher names
and requested label names are capped at 256 bytes. Selector syntax remains the
legacy ASCII-name subset; this is not all Prometheus UTF-8 selector grammar.
Full expressions, ranges, unsupported offsets, hints, `query`, malformed
selectors and unknown parameters reject rather than falling back to an unfiltered
scan. Duplicate scalar parameters reject, including across query/form sources;
selectors from both sources are combined.

## MCP

Use `discover_metrics` with `tenant` and `mode` (`names`, `values`, `series`).
Values requires `label`; series requires `selectors`, an array of selector strings.
Optional `start_ts_ns` / `end_ts_ns` are exact signed int64 nanoseconds. HTTP and
MCP share discovery semantics, admission and budgets. Tool text contains the
same success envelope. The schema rejects unsupported properties such as `limit`.

## Completeness and differences from Prometheus TSDB metadata

This API describes **retained samples**, not instant-vector lookback results or a
catalog of every historically observed series. A label set needs at least one
stored sample inside the requested interval, at the time granularity below.
Stale/NaN/infinite sample values do not remove its labels from discovery.
Expired records never supply suggestions. This is not full Grafana
datasource/browser or deployed-client parity.

**Time granularity.** With metrics compaction enabled, Pulse keeps a series
catalog per UTC hour (see [series catalogs](#series-catalogs)). A UTC hour that
has one is answered as a whole: a series with a sample anywhere in that hour is
reported for any interval overlapping the hour. Hours without a catalog use
exact sample times. Grafana Mimir behaves alike, rounding `start` and `end` to
its 2 h (recent) to 24 h (compacted) block boundaries, so Pulse is never coarser
than Mimir. Prometheus TSDB can additionally report series without samples in
the interval from block or tombstone metadata; Pulse does not.

Empty-valued labels project as absent, following Prometheus identity semantics.
Thus a stored `host=""` supplies neither a `host` name nor an empty value, and
otherwise identical series with empty versus absent labels coalesce. Matching
still treats both as empty. This is a read-only discovery projection: raw
`query_metrics` records and typed OTLP metadata are not rewritten or discarded.
Names/values use byte order; series use pairwise label name/value order. JSON
object key order is not a contract; native/reference results are semantically,
not byte-for-byte, equivalent.

## Series catalogs

Scanning samples costs one row per stored sample, so a busy tenant exceeds the
scan budgets within minutes of history. With metrics compaction and hour
finalization enabled (`PULSE_METRICS_COMPACTION_ENABLED=true`, and
`PULSE_METRICS_FINALIZE_ENABLED` left at its default `true`), Pulse therefore writes immutable
**series catalogs**: one or more objects per tenant and UTC hour listing that
hour's distinct series, plus three small sections derived from them: label
names, label name/value pairs, and the label names of each metric. Discovery
reads an hour's catalogs and only the sample segments no catalog covers yet,
so its cost grows with the number of series and label values, not samples:

| Request | Section read |
| --- | --- |
| `labels` without `match[]` | label names |
| `labels` with selectors on `__name__` only, such as `{__name__=~".+"}` | label names per metric |
| `label/<name>/values` without `match[]`, or with selectors on `<name>` only | label values of `<name>` |
| Everything else, including `series` | series, skipping metrics an exact `__name__` matcher excludes |

The background maintenance worker builds them. Recent hours are handled on
the metrics grouping lane (every compaction interval, 60 s by default) before
grouping, so data newer than about one interval is read from samples. Older
hours are handled on the historical lane after finalization. Each pass adds
a small delta catalog listing only series the hour's catalogs do not have yet.
After eight catalogs, or once the hour has settled, they are merged into one.
Grouped and finalized segments made from covered segments stay covered without
another read. Catalogs are written to the metrics manifest under keys
containing `-rollup-catalog-`, retired and deleted like other replaced
segments, and expire with retention. Retention-managed format-3 prefixes are not catalogued
yet; their discovery reads samples.

Catalogs need no configuration and no migration: existing history is
catalogued newest first, up to 2 million sample rows per pass. They are safe
during a rolling deploy and after a rollback: earlier releases read the
`-rollup-` in a catalog key as an hourly rollup, so they never read it as
samples, never use it for rollup reads (it spans the hour rather than one
instant), and retire it when they finalize its hour. That hour is then
answered from samples until it is catalogued again.

## Resource limits and storage costs

A request computes a **complete result or an error**, never silently sampling
metadata to fit budgets. An explicit HTTP `limit` can truncate that completed
result with a warning. Fixed bounds are 5000 distinct entries, 1 MiB dictionary-key
bytes and an independent 1 MiB encoded discovery-payload ceiling (including
success-envelope headroom). Outer JSON-RPC/MCP wrapping adds bytes outside that
payload limit. Narrow queries when these bind; no `limit` parameter bypasses them.

S3 discovery shares one scan across every OR selector: at most 1024 objects,
128 MiB downloaded segment bytes and one million rows, further reduced by
configured query limits. A catalog charges the rows of the section row groups
it reads; an uncovered sample segment charges all its actual Parquet footer
rows, even if its samples are outside the requested interval. Catalogs are
downloaded whole, so their bytes count in full. Missing-source
retries retain spent scan budgets and restart dictionary state, not mix snapshots.
Metadata/page/deadline budgets remain independent. Whole-retention scans are the
default when times are omitted; a small result is not a small scan.

Single-selector proven manifest summaries can prune sources; OR selectors scan
conservatively. Pruned objects are not checked for existence or corruption. There are still whole-object GETs, **not range reads or external
postings**. Native code projects timestamps/canonical labels only, deduplicates
immutable dictionary keys within 1024-row batches, and accumulates dictionaries
without expanding sample values or OTLP metadata into BEAM. Each decoded row
charges one work unit; distinct in-window dictionary keys additionally charge
one plus label count plus total matcher count before predicates. Per-attempt
bounds are five million work units and 16 MiB canonical-byte probes. Repeated
samples do not pay full canonical parsing per row. Batch/source layout can change
work costs, and high-cardinality inputs can still fail.

The bounded reference for non-native adapters instead admits at most 100,000
selected records with a sentinel; repeated equal-label runs reuse validation and
matching. It has independent probe/work/dictionary/result limits. Neither path's
bookkeeping budgets are total Arrow/parser/container/native memory guarantees.
Values/OTLP/unrequested columns are not integrity-scrubbed; malformed selected
canonical labels fail whole, including on nonmatching selectors.

HTTP errors: 400 invalid parameters, 401 unauthorized, 429 busy, 422 resource
limits, 500 invalid stored data/execution failure, 503 storage failure and 504
query timeout. Errors have no partial `data` result.

Serving applications require matching metric codec API `{2,2,1,1,1,1}` (metadata/start timestamps,
OTLP, postings, discovery, footer planning, streaming reads). Upgrade every serving app/native pair before using
these routes with pooled routing. Series catalogs additionally require metric catalog
API 1 on every instance that serves discovery or runs metrics maintenance; they add
an object type but change no existing segment format, and need no metadata migration.
Existing rich-data/keyed-publication writer upgrade rules still apply. Local startup
cannot fence older serving pools.
