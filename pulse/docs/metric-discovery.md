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

At most 16 selectors, 64 total matchers, eight regexes, 1024 bytes per regex and
16 KiB total selector text/matcher name-value bytes are accepted. Matcher names
and requested label names are capped at 256 bytes. Selector syntax remains the
legacy ASCII-name subset; this is not all Prometheus UTF-8 selector grammar.
Full expressions, ranges, unsupported offsets, hints, `query`, `limit`, malformed
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
stored sample inside the requested interval. Stale/NaN/infinite sample values do
not remove its labels from discovery. Expired records never supply suggestions.
Prometheus TSDB metadata APIs may include inactive series with no samples in the
requested interval because of block/tombstone metadata; that behavior is not
reproduced. This is not full Grafana datasource/browser or deployed-client parity.

Empty-valued labels project as absent, following Prometheus identity semantics.
Thus a stored `host=""` supplies neither a `host` name nor an empty value, and
otherwise identical series with empty versus absent labels coalesce. Matching
still treats both as empty. This is a read-only discovery projection: raw
`query_metrics` records and typed OTLP metadata are not rewritten or discarded.
Names/values use byte order; series use pairwise label name/value order. JSON
object key order is not a contract; native/reference results are semantically,
not byte-for-byte, equivalent.

## Resource limits and storage costs

A request returns a **complete result or an error**, never a sampled/truncated
metadata dictionary. Fixed bounds are 5000 distinct entries, 1 MiB dictionary-key
bytes and an independent 1 MiB encoded discovery-payload ceiling (including
success-envelope headroom). Outer JSON-RPC/MCP wrapping adds bytes outside that
payload limit. Narrow queries when these bind; no `limit` parameter bypasses them.

S3 discovery shares one scan across every OR selector: at most 1024 objects,
128 MiB downloaded segment bytes and one million actual Parquet footer rows,
further reduced by configured query limits. Every fetched source's full header
rows count, even if its samples are outside the requested interval. Missing-source
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

Serving applications require matching metric codec API `{2,2,1,1,1}` (metadata/start timestamps,
OTLP, postings, discovery, footer planning). Upgrade every serving app/native pair before using
these routes with pooled routing. No file format changes or metadata migration
are introduced by this read-only API; existing rich-data/keyed-publication writer
upgrade rules still apply. Local startup cannot fence older serving pools.
