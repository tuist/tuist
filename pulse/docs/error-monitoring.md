# Error monitoring (experimental)

Sentry ingestion and bounded, ad hoc diagnosis work without a monitoring worker.
An optional S3-derived index adds retained-history issue summaries and a replayable
change feed for agents. It is a bounded experimental implementation, not Sentry
parity or a throughput/latency guarantee. Enable it separately from ingestion.

The original Parquet logs remain the only event authority. Successful ingestion
still waits only for the segment PUT and log-manifest conditional publication;
index failure never turns accepted events into unaccepted events. Nodes need no
SQL database, durable local disk, queue, or leader election.

## Enable the worker

```sh
PULSE_ERROR_PROJECTION_ENABLED=true
PULSE_ERROR_HISTORY_DAYS=1
PULSE_ERROR_PROJECTION_INTERVAL_MS=5000
```

Helm equivalents are `sentry.projectionEnabled`, `sentry.historyDays` and
`sentry.projectionIntervalMs`. Defaults are `false`, `1` and `5000`. History is
1–365 whole days; cadence is 1000–60000 milliseconds. Invalid integers fail
startup. Only S3-backed nodes start the worker. It discovers projects from
`PULSE_SENTRY_PROJECTS_JSON`; keep project-to-tenant identity fixed.

One pass handles one configured project and up to 32 previously unprocessed
committed segments. Projects rotate, so with N projects each is visited roughly
every N × cadence, plus work duration. Eligible nodes use rendezvous ownership;
conditional S3 writes fence overlapping work during membership changes. Work
shares the reserved bounded background query admission with alert evaluation.

Set log retention comfortably longer than the monitoring history plus expected
downtime/catchup. The index cannot recover events that raw retention already
removed. It never delays raw retention to protect a stalled worker.

## Poll changes, then fetch payloads separately

Tenant bearer credentials authorize these read-only MCP tools; SDK DSN keys do
not. Both tools require `tenant` and numeric `project`, accept `limit` (1–100,
default 50), and return `next_cursor`:

- `list_error_changes`: ordered `baseline_ready`, `new_in_retained_history`,
  `issue_observation`, `error_rate_increase` and `reset` changes. Even an empty
  response returns a cursor to reuse for the next poll.
- `list_indexed_error_issues`: small issue summaries with exact deduplicated
  `retained_count`, occurrence `first_seen_ns`/`last_seen_ns`, title, service and
  `latest_example` containing an event ID and timestamp. An incomplete
  reconciliation returns `projection_catching_up`, never partial counts.

For a payload, call `query_errors` with the same tenant/project, the example's
`event_id`, and `start_ts_ns`/`end_ts_ns` equal to its occurrence timestamp. Raw
retention may remove that payload before it is fetched; handle reset/not-found
and empty results rather than interpreting them as recovery.

Persist change cursors in the agent runtime, durably and independently of Pulse
nodes. Process changes idempotently using `change_id`; after acting, save the
returned cursor. A crash between acting and saving can replay the same change.
Subscriptions are not implemented; polling is the durable contract.

## Error-rate findings for agent workflows

The enabled monitoring worker also runs `error-count-ratio-v1`; no separate
detector service or model is required. Poll `list_error_changes` through MCP
with `tenant`, numeric-string `project` and the last durably accepted `cursor`.
An `error_rate_increase` change is a concrete investigation trigger, not an
instruction or permission to change infrastructure.

The detector compares the latest two **completed, epoch-aligned five-minute
windows**, independently for each issue/service. Intervals include their start
and exclude their end. It emits when the preceding window has at least five
deduplicated events and the latest has at least three times that count (therefore
at least fifteen). This measures error occurrences per equal time window, **not
the fraction of requests that failed**, seasonality or statistical significance.
Zero/sparse baseline groups do not qualify; use existing novelty changes for
new issues. Thresholds/windows are fixed in this detector version.

Each finding includes `detector`, `issue_id`, `service`, `baseline` and `current`
with `start_ns`, `end_ns`, `count`, the `ratio`, `coverage: retained_snapshot`,
the inspected snapshot's `source_etag` and `history_floor_ns`, and up to three
recent compact `evidence` examples with event ID, occurrence
timestamp, title and service. These examples are stored in the committed replay
page, not fetched through raw pointers; they remain readable after source expiry
until the replay floor passes them. They are **not full stack traces/payloads**;
fetch those through `query_errors` while raw history remains available.

The first complete detector pass after bootstrap, source reset or upgrade from
a worker without this detector establishes a baseline without emitting historical
findings. Later passes can discover late events in the latest window. Each
issue/service emits at most once per evaluated window, even if counts fluctuate
and later cross the threshold again. Counts are observations of one committed
retained snapshot, not proof that exporters finished delivering the window.
Older windows are not backfilled after downtime; an unavailable worker is not
evidence of health. Existing unknown-lag and reset semantics still apply.

Responses expose `rate_detector` with `detector`, `status` and, when available,
`window_end_ns`. Status is `baseline_pending`, `catching_up`,
`insufficient_history` or `ready`. `ready` means a complete inspected snapshot
was evaluable, **not that the application is healthy or ingestion is current**.
Incomplete source reconciliation emits no rate findings; insufficient retained
history cannot form a baseline. A later lower count does not emit a resolution.

Measurements, detector deduplication and changes publish in the same projection
root CAS. Failed/losing publications cannot independently emit findings.
Upgrade every projection worker before relying on detector progress: older
workers do not evaluate rate windows. Consumers must accept the additional
change kind and `rate_detector` response field. Raw ingestion, storage/native
formats and retention defaults are unchanged; processing-only ingestion is
still not implemented. Retained findings/examples remain sensitive tenant data
subject to the derived-prefix erasure procedures below.

## What newness and counts mean

The scope is one tenant, one project, and grouping version `sentry-group-v1`.
Newness means **new in this retained history**, never first ever, new release,
resolved, or reopened. The explicit floor is the greater of the raw log-retention
floor and index time minus `historyDays`. Evidence below it is forgotten. An
issue can therefore become new-in-retained-history again after its last evidence
expires. Changing the configured horizon forces a new baseline.

Bootstrap and rebaseline collect history without announcing historical issues
as new. Only complete reconciliation publishes issue changes or exact counts.
`indexed_at_ns` is discovery/publication time; occurrence timestamps are kept
separate. A late upload inside the horizon is discovered through its committed
segment identity even if its occurrence time precedes the last agent poll.

The index separately remembers processed committed segment keys and deduplicates
occurrences by `(tenant, project, event_id)`. Retries in different random segments
count once. Conflicting copies deterministically select the greatest occurrence
timestamp, then the SHA-256 digest of canonical JSON `[payload, service, issue_id]`;
receipt time does not choose the winner. Counts are not summed segment totals,
and deduplication does not extend beyond the explicit retained-history horizon.

Ordinary logs with Sentry labels but without a valid structured error record are
excluded from summaries and changes; their segments are still marked processed,
so they cannot stall reconciliation. They remain available through raw log
queries and consume scan budgets.

## Freshness, gaps, and resets

Responses expose the last inspected source manifest's ETag, `indexed_at_ns`,
`history_floor_ns`, `horizon_ns`, `backlog_segments_at_index`,
`complete_at_index`, `baseline_pending`, `sequence` and `replay_floor`.
`lag_status` is `unknown` and `lag_ns` is null: zero backlog in that inspected
snapshot does not prove that no newer ingestion exists. Alert on stale index
time in your agent runtime; a failed/overloaded pass leaves the old index intact.

Known unprocessed inputs disappearing force a reset. The worker also resets if
the raw retention floor moves beyond its previously inspected history floor:
an entirely unseen segment could have appeared and expired during downtime.
Current manifests and processed IDs alone cannot disprove that gap. A reset
change records the reason, `last_reset_reason` remains visible, and a fresh
baseline suppresses novelty claims about the missing interval. This guarantee
requires Pulse-managed retention; do not independently expire live segment or
manifest objects using bucket lifecycle policies or out-of-band writes.

Changes live in immutable, digest-checked pages referenced by the same conditional
root that publishes deduplication, summaries and source coverage. Failed or
unconfirmed publications cannot independently emit a change. Retain the last
64 pages, each holding up to 64 changes: this is a count bound, **not a promised
time window**. The root advances `replay_floor` before obsolete pages are deleted.
A cursor below that floor, a missing retained page, a recreated index, or a
changed cursor-signing secret returns `reset_required`. Re-read the baseline and
resume at the advertised floor; never silently skip changes. Issue-list cursors
also reset if their result snapshot changes. Cursors are authenticated, bound to
tenant/project/operation, and require the same `SECRET_KEY_BASE` across nodes.

## Capacity and operations

Per project the index holds at most 4096 candidate segments, 20,000 stored
occurrence copies before deduplication, and an 8 MiB conditional root. A pass
reads at most 32 new segments, less than 64 MiB of segment bytes and 100,000
declared rows. Independently, a **32 MiB decoded-column budget** is cumulative
across all newly decoded segments in that pass, including rows later filtered
out. String lengths, including dictionary repetitions, are preflighted before
Arrow materialization; batch sizing uses actual decoded values rather than the
Sentry event-size cap, which does not apply to ordinary logs in shared segments.
Highly compressed payloads cannot bypass it; exhaustion returns
`query_decoded_limit` and publishes no progress or changes from that pass.
Indexed titles are at most 2000 UTF-8 bytes, without changing event grouping.
Fresh source enumeration also obeys query metadata/scan budgets;
unknown error/project summaries must scan. Each replay page is at most 256 KiB.
Work runs under the query deadline, heap and admission limits. Exceeding a bound
fails the pass rather than truncating counts or manufacturing continuity.
Small segments, high retry volume, long history and high-cardinality issues can
reach these bounds well before ordinary log queries do. Reduce history, improve
ingest batching, or leave monitoring disabled until a partitioned index is
appropriate for your measured volume. Capacity failure never blocks ingestion.

Derived objects live under `tenants/<tenant>/errors/v1/project=<project>/`.
Obsolete replay-page deletion is best-effort. Interrupted publications and losing
writers can leave unreferenced pages; there is no automatic orphan sweep yet.
To reclaim them, stop all projection workers first, load each project's current
head, and remove only page objects not referenced by that head. Do not run an
uncoordinated lifecycle rule over this prefix. Disabling the worker does not
delete its last index or revoke tenant read access; include this derived prefix
in explicit tenant erasure procedures. Bucket versioning retains old object
versions according to the bucket's separate policy.

No native error alert evaluator, issue lifecycle, symbolication, notifications,
self-service project registry, or lifetime counters are included. See
[error tracking](error-tracking.md) for SDK delivery limitations and the useful
diagnosis-only contract.
