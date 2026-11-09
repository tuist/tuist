# Retention

> [!WARNING]
> Retention is experimental. It deletes data, it is one-way once enforced, and
> it has not been validated against every S3-compatible provider. Run it on a
> test bucket first and keep independent monitoring of Pulse.

By default Pulse keeps every acknowledged record indefinitely. Event-time
retention lets you keep logs, metrics and traces for a fixed number of days instead,
without bucket lifecycle rules. Pulse decides what has expired from record
timestamps, records that decision in the bucket, and deletes objects itself.

Trace retention uses **span start** timestamps. Search and `get_trace` hide
expired spans even inside mixed-age segments. Trace assembly reports its
snapshot's `retention_floor_ns` so clients can distinguish retention boundaries
from exporter completeness. See [traces](traces.md#retention).

## How it works

Each tenant and signal has a **retention floor**: a timestamp below which
records are expired. A maintenance pass moves it forward to `now - days`, and it
never moves back. Records at exactly the floor are kept.

- **Ingest** rejects a whole request if any of its records is older than the
  floor, or more than the future-skew allowance ahead of the node's clock.
  Records without a timestamp count as too old. Unkeyed OTLP traces can instead
  report out-of-retention spans individually through `partialSuccess` after
  safety preflight; keyed payloads are never rewritten. Publication always
  checks the latest committed floor, so a concurrent advance can still reject
  a queued trace batch as a whole. Nothing is silently dropped.
- **Queries** never return records below the floor, even when they are inside
  an object that also holds newer records.
- **Deletion** happens in whole time buckets after a grace period (one hour by
  default). The grace gives queries that started before the floor moved time to
  finish, but it is not a guarantee: a query that finds a data object or
  manifest page already deleted restarts once against a fresh manifest, then
  fails.

By default enforcement keeps each prefix's paged (format 4) manifest, see
[manifest format](configuration.md#manifest-format). The floor is stored in the
root and moves in whole hours. Each pass retires segments whose newest record is
older than the floor, rewriting at most 32 manifest leaves, and drops pages that
only hold forgotten history. Retired segments are deleted by the same cleanup as
compaction sources: after the grace period, and with
[manifest backups](configuration.md#manifest-backups) on (the default) only
once a backup records the retirement, so the newest backup always restores.
Metric [hour finalization](configuration.md#long-dashboard-and-alert-ranges)
keeps running and skips expired hours. An existing format-4 or flat prefix needs
no migration: the first pass sets its floor (a flat root is converted to format 4
first), and ingest keeps running throughout.

With `PULSE_RETENTION_MANIFEST_FORMAT=bucketed`, enforcement instead converts
each manifest to the bucketed format 3 described below, which deletes whole time
buckets but is neither backed up nor finalized. Prefixes already in format 3
stay in format 3. The rest of this section describes format 3. Its root manifest
stays the single conditionally written authority and holds:

- the floor, the recorded duration and a fixed bucket width;
- a small inline list of the most recent segments (at most 256 entries / 64 KiB);
- one descriptor per time bucket (a hard ceiling of 2,048, and the root is capped
  at 512 KiB independently).

Older entries live in immutable pages next to the segments: leaves of at most
256 entries / 64 KiB and per-bucket indexes of at most 1,024 references /
512 KiB. Pages are written before the root that references them and are never
modified. Superseded pages are deleted together with their bucket.

The bucket width is chosen once, at activation, as the smallest whole number of
hours that fits the **retention window** in 508 buckets, leaving room for 512
descriptors including headroom. The window is the duration plus the deletion
grace (or the compaction grace, if longer) plus the future-skew allowance,
because expired buckets stay in the manifest until their grace has passed. This
keeps the root within its byte budget even with long tenant names. With the
default grace and skew, the width is one hour for up to 21 days, two hours for
30 days, 18 hours for 365 days, and 173 hours for the 3,650-day maximum; a much
longer grace or skew widens it. The width is stored in the manifest and cannot
be changed in place.

Every maintenance pass and every `apply_policy/5` call rechecks the window
against the stored width. If you later raise the grace or future skew so far
that the window no longer fits, maintenance passes for that tenant/signal fail
with `:retention_capacity` and the floor stops moving until you revert the
change. Ingest keeps working, but expired data stops being removed, so the
manifest eventually fills. Treat the grace period and future skew as fixed once a prefix
is enforced: the stored width is sized for the window at activation, and the
spare room is often only a few hours.

Activation also creates a small, immutable `.managed` marker object in the
tenant/signal prefix. It holds a random seed from which conversion derives its
page and bucket identities, so a retried or restarted conversion rewrites the
same pages instead of new ones. From then on Pulse refuses to rebuild that
manifest by listing objects: if the manifest is missing, reads and writes fail
with an error instead of resurrecting expired or unpublished data.

Prefixes that are not retention-managed keep their flat or paged (format 4,
see [manifest format](configuration.md#manifest-format)) manifest. Converting a
paged prefix to format 3 reads its pages into one list under the same 16 MiB
conversion limit as a flat manifest, then converts it to format 3. Ordinary
queries and appends read their manifests without a size limit in every mode,
as before. When a node does not yet know a prefix's format (after a restart, for
example), its first read is capped at 512 KiB, the format-3 limit; a larger
legacy manifest costs one extra, unlimited read.

## Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `PULSE_RETENTION_ENABLED` | `false` | Run the background retention and cleanup worker even when all durations are `0`. The worker also runs whenever any duration is positive. |
| `PULSE_LOGS_RETENTION_DAYS` | `0` | Log retention in whole days, `0..3650`. `0` stops advancing the floor. |
| `PULSE_METRICS_RETENTION_DAYS` | `0` | Metric retention in whole days, `0..3650`. |
| `PULSE_TRACES_RETENTION_DAYS` | `0` | Trace retention by span start in whole days, `0..3650`. |
| `PULSE_RETENTION_MODE` | `observe` | `observe`, `enforce`, or `paused`. See [Modes](#modes). |
| `PULSE_RETENTION_MANIFEST_FORMAT` | `paged` | Manifest of enforced prefixes: `paged` keeps format 4 (backups, hour finalization), `bucketed` converts to format 3. Prefixes already in format 3 stay there. With `PULSE_MANIFEST_FORMAT=flat`, enforcement uses format 3. |
| `PULSE_RETENTION_DELETE_GRACE_MS` | `3600000` | Time between expiry being committed and objects being deleted, `60000..2592000000`. |
| `PULSE_RETENTION_INTERVAL_MS` | `30000` | Maintenance cadence, `1000..3600000`. |
| `PULSE_RETENTION_DELETE_LIMIT` | `512` | Maximum DELETE attempts per node per `PULSE_RETENTION_INTERVAL_MS`, `1..512`, shared by retention and compaction cleanup of retention-managed prefixes. At most four run at once. |
| `PULSE_RETENTION_TIMEOUT_MS` | `30000` | Deadline for one maintenance operation, `1000..600000`. |
| `PULSE_RETENTION_MIGRATION_TIMEOUT_MS` | `600000` | Deadline for converting one existing manifest during enforcement, `30000..3600000`. Normal maintenance keeps `PULSE_RETENTION_TIMEOUT_MS`. |
| `PULSE_RETENTION_FUTURE_SKEW_MS` | `600000` | How far ahead of the node clock a record may be, `0..86400000`. Applies to retention-managed prefixes. |
| `PULSE_RETENTION_SWEEP_HORIZON_DAYS` | twice the recorded days plus two | Days of already-expired partitions that orphan sweeps revisit, `1..7302`. |

Out-of-range or malformed values stop the node at startup. The chart exposes the
same settings under `retention.*`; see [deployment](deployment.md).

Use identical settings on every node that shares a bucket. The configured
durations and mode also decide how a node treats ingest and queries, and any
node with a positive duration runs the worker.

## Modes

| Mode | Floor advancement | Deletes already committed work | Converts manifests |
| --- | --- | --- | --- |
| `observe` | No, preview only | Yes | No |
| `enforce` | Yes, when the duration is positive | Yes | Flat roots to format 4 (`paged`), or any root to format 3 (`bucketed`) |
| `paused` | No | No | No |

A committed floor keeps being enforced on ingest and queries in every mode,
including `paused` and with the duration set back to `0`. Neither rewinds the
floor or restores deleted data.

`paused` is the emergency stop. It stops new maintenance work on each node as
that node picks up the setting; storage calls already in flight finish.

Set `PULSE_RETENTION_ENABLED=true` before you set the durations back to `0` if
expired buckets are still waiting for cleanup. With all durations at `0` and
the flag off, the worker does not start, and that committed work and its objects
stay in place until it runs again.

Keyed segment uploads are now create-only, with bounded exact-byte streaming
verification after a failed create. The latest retention floor and retirement
records still fence publication; a recreated retired source only rearms cleanup,
never duplicates a replacement. Failed publication may leave orphans; flat scopes
still lack a general orphan sweeper. A permanent HTTP409 byte conflict is not
permission to delete source history or change retry keys. See
[keyed ingestion and upgrade requirements](keyed-ingestion.md).

## Enabling retention

1. **Upgrade every Pulse process that touches the bucket to the same release,
   in `observe` mode, and finish the rollout.** Releases before 1.32 ignore a
   format-4 floor (they would serve and accept expired data), and releases
   without retention cannot read format-3 manifests. Do not enforce while any older
   reader, writer or compactor can still reach the bucket; stop or fence them
   first. Rolling to a retention release does not by itself make old and new
   versions safe to overlap after enforcement.
2. **Keep manifest backups on (format 4) or turn on bucket versioning (format
   3)**, and decide how long to keep them. See [Recovery](#recovery-and-backups).
3. **Check clocks.** Expiry and the future-skew check use wall-clock time.
   Nodes must agree well within the grace period and the skew allowance.
4. **Preview.** With durations set and the mode still `observe`, inspect each
   tenant/signal from a running node (see [Operating retention](#operating-retention)).
5. **Switch to `enforce`.** The worker sets each tenant/signal's floor (in
   `bucketed` mode it first converts the manifest and creates the marker). Expired data stops appearing
   in queries right away; objects are deleted after the grace period.

**With `bucketed`, ingest pauses for a prefix until it is converted.** In
`enforce` mode, an
append to a tenant/signal that already has data in the old format is rejected
with `:retention_migration_required`, a retryable error, until the worker has
converted it. Collectors keep retrying and resume once conversion lands. A
tenant/signal with no data yet is converted immediately by its first append.
Plan the switch for a time when a short ingest delay per tenant is acceptable,
and keep collector retry horizons longer than the expected conversion time.

Conversion has its own deadline, `PULSE_RETENTION_MIGRATION_TIMEOUT_MS` (ten
minutes by default). It reads the existing manifest with a 16 MiB limit. Time
buckets that are already wholly closed at conversion are recorded as closed
cleanup work (up to 262,144 objects per work bucket) and deleted after the grace
period like any other expired bucket, rather than getting their own descriptors.
**Automatic conversion refuses a manifest larger than 16 MiB.** Such a prefix
stays readable, but in `enforce` mode its appends keep returning
`:retention_migration_required` until it is converted. It needs an explicit
offline conversion (see [Converting large manifests](#converting-large-manifests)).

### Converting large manifests

`convert_offline/4` converts one tenant/signal whose manifest is above the
automatic limit, with explicit resource bounds:

```sh
kubectl -n observability exec deploy/pulse -- /app/bin/pulse rpc '
  config = Map.new(Application.fetch_env!(:pulse, Pulse.Storage.S3))
  Pulse.Storage.S3.Retention.convert_offline("production", "metrics", config,
    max_legacy_bytes: 67_108_864, heap_words: 64_000_000, timeout_ms: 600_000)
  |> IO.inspect()'
```

| Option | Range | Default | Meaning |
| --- | --- | --- | --- |
| `max_legacy_bytes` | `1..268435456` | required | Largest manifest the call may read. |
| `heap_words` | `1000000..128000000` | `64000000` | Heap limit of the conversion process; it is killed if it exceeds it. |
| `timeout_ms` | `1000..600000` | `600000` | How long the call waits for the result. |

Before running it:

- Set a positive duration for the signal; the call refuses `0`.
- The retention worker must be running on that node (`PULSE_RETENTION_ENABLED`
  or a positive duration). Set `PULSE_RETENTION_MODE=paused` so the background
  worker stays idle; the call performs the conversion itself. It refuses to start
  while another retention task is running on the node.
- **Stop every writer and compactor for that tenant/signal**, on every node:
  route its collectors away and disable compaction. The conversion is a
  conditional write against the manifest it read, so concurrent writes make it
  fail and start over.

On success it returns the same result as a maintenance pass. If it returns
`:migration_timeout`, the conversion keeps running in the background and may
still complete: run `inspect_policy/4` until the format is `3` or the task has
ended before retrying, then restore traffic and the previous mode.

After a prefix is converted, rolling back to a release without retention is not
supported. Fix forward with a release that understands format 3.

## Changing or disabling retention

The duration recorded in a manifest is authoritative. A worker whose configured
duration differs from it refuses to advance the floor for that tenant/signal and
reports `:retention_policy_mismatch`. Changing the environment alone does not
change the recorded policy.

To change it, update the configuration on every node, then apply the change
explicitly for each tenant and signal:

```sh
kubectl -n observability exec deploy/pulse -- /app/bin/pulse rpc '
  config = Map.new(Application.fetch_env!(:pulse, Pulse.Storage.S3))
  Pulse.Storage.S3.Retention.apply_policy("production", "metrics", config, 30, 14)
  |> IO.inspect()'
```

`apply_policy/5` takes the tenant, the signal (`"logs"`, `"metrics"` or `"traces"`), the
storage configuration, the duration you expect to be recorded now, and the new
duration (`1..3650`). It is a conditional write: it fails with
`:retention_policy_mismatch` if the recorded duration is not the expected one,
and with `:retention_capacity` if the new window (duration plus grace plus
skew) does not fit the recorded bucket width in 508 buckets. A manifest activated
with a short duration, and therefore a narrow width, can only be extended to
about 21 days per hour of width with the default grace and skew.

- **Shortening** makes more data expire on the next pass.
- **Lengthening** only affects data that has not expired yet. Deleted data cannot
  be restored.
- **Disabling**: set the duration to `0`. The floor stops moving, the committed
  floor stays enforced, and pending cleanup continues only while
  `PULSE_RETENTION_ENABLED=true` keeps the worker running.
  The prefix stays in format 3.

While the floor is not moving (duration `0`, `observe` or `paused` on a converted
prefix), buckets stop expiring and the manifest's descriptor budget eventually
fills. Ingest for that tenant/signal is then rejected with a capacity error
until the floor moves again. Treat these as temporary states on converted
prefixes.

## Operating retention

Run inspection on a running node so it uses the node's configuration:

```sh
kubectl -n observability exec deploy/pulse -- /app/bin/pulse rpc '
  config = Map.new(Application.fetch_env!(:pulse, Pulse.Storage.S3))
  Pulse.Storage.S3.Retention.inspect_policy("production", "metrics", config)
  |> IO.inspect()'
```

`inspect_policy/4` never writes. It reports:

| Field | Meaning |
| --- | --- |
| `format` | Manifest format; `3` once converted. |
| `desired_days`, `floor_ns`, `proposed_floor_ns` | Configured duration, committed floor, and the floor a pass would set now. |
| `inline_segments`, `buckets`, `pending_buckets` | Entries in the inline tail, time buckets, and expired buckets still being cleaned up. |
| `root_bytes` | Encoded size of the root manifest (limit 512 KiB). |
| `max_leaf_refs`, `max_bucket_mutations`, `max_bucket_written_bytes` | The largest bucket's page references (limit 1,024), rewrites (limit 10,000) and metadata bytes written (limit 256 MiB). |
| `capacity_ratio` | The highest of the usage/limit ratios above and the descriptor count over 2,048. At `1.0` the next write that needs that capacity fails. |
| `reclaimed_through_ns` | Watermark below which orphan sweeps may delete objects. |
| `catchup` | The active catch-up job, if any. |

Keep `capacity_ratio` well below `1.0`. A ratio that keeps rising usually
means cleanup is falling behind, a single bucket is receiving very many late
writes, or the grace period is long compared with the retention duration.

Expired data is removed in stages, each resumable after a crash or restart:

1. A pass advances the floor and marks every bucket that ended at or before it
   as expiring. Expiring buckets accept no new writes and are not read by new
   queries.
2. After the grace period, the segments the bucket references are deleted.
3. Then the bucket's own metadata pages are deleted, and finally its descriptor
   is removed from the root.

Deletion is admitted node-wide, not per tenant: each node runs at most four
DELETE requests at once and makes at most `PULSE_RETENTION_DELETE_LIMIT`
DELETE attempts per `PULSE_RETENTION_INTERVAL_MS`, shared by retention and by
compaction cleanup of retention-managed prefixes. Each operation also stops at
`PULSE_RETENTION_TIMEOUT_MS`. A failing object is retried on later passes
without blocking other buckets.

Each pass visits a bounded number of tenant/signal scopes. The worker discovers
tenants from the bucket a few at a time, without listing every object, and also
covers tenants with recent local activity. With many tenants, a full cycle takes
several passes.

Objects that were uploaded but never published (a crashed request, a lost
response, an upload that finished after its bucket expired) are not referenced
by any manifest. Orphan sweeps list expired date partitions, one page at a time
within `PULSE_RETENTION_SWEEP_HORIZON_DAYS`, and delete segment objects whose
newest record is below a floor that has itself been committed for at least the
grace period. They also remove leftover metadata of buckets that are gone.
Objects that appear outside the horizon, for example after a long outage, are
not revisited automatically; start a catch-up for them.

### Catching up on old orphans

`start_catchup/4` creates a durable catch-up job for one tenant/signal. It
revisits everything from `from_ns` up to the current `reclaimed_through_ns`,
including ranges outside the normal sweep horizon:

```sh
kubectl -n observability exec deploy/pulse -- /app/bin/pulse rpc '
  config = Map.new(Application.fetch_env!(:pulse, Pulse.Storage.S3))
  from = DateTime.to_unix(~U[2026-06-01 00:00:00Z], :nanosecond)
  Pulse.Storage.S3.Retention.start_catchup("production", "metrics", config, from)
  |> IO.inspect()'
```

The job is stored in the manifest, so it survives restarts and ownership moves.
While it is active it replaces that scope's normal sweep: each pass lists at
most 128 keys from one date partition and 128 from one expired metadata slot,
under the same node-wide delete admission. If any delete fails or is not
admitted, the job starts another complete cycle after finishing the current
one, while healthy ranges keep being processed. It clears itself only after a
cycle without failures. Follow it through the `catchup` field of
`inspect_policy/4`.

Only one job can exist per tenant/signal, and `from_ns` must be below the
current watermark; otherwise the call returns `:invalid_catchup`. A catch-up
over a long range takes many passes: each pass handles about 256 keys for that
scope.

## Capacity

Retention keeps metadata proportional to the retained window, not to how long
the bucket has existed. It still has limits, and exceeding them returns an
explicit capacity error rather than dropping data:

- one owner publication can touch at most four time buckets and admit at most
  256 segments / 64 KiB of new encoded wire metadata; additional callers defer;
- live indexes preserve both byte and leaf-reference headroom for expiry;
  trace references cap at 4 KiB, with optional summaries omitted when needed;
  trace-heavy buckets can reach byte capacity well before 1,024 references;
  overflow is retryable until the bucket rolls over, not a throughput promise;
- each bucket's metadata (current and superseded pages) is capped;
- a root, page or index that would exceed its size budget is refused;
- a query reads at most 128 manifest pages plus two per time bucket in the
  manifest, and by default at most 8 MiB of manifest data, within one deadline
  shared with its retry. Exact-ID trace queries add 64 KiB per overlapping live
  bucket to that default, capped at 32 MiB total; explicit configured byte
  limits are never raised. A query reads one index per overlapping time bucket plus the leaves
  that match, so long ranges work as long as they stay within the byte budget
  and the segment scan limits. Very dense ranges fail with `:metadata_scan_limit`
  or the usual scan-limit error rather than returning partial results;
- maintenance operations read at most 128 manifest pages and 8 MiB each.

Each node caches up to 512 immutable manifest pages in memory and evicts the
least recently used ones once the cache's own table memory plus the encoded
size of the cached pages exceeds 16 MiB, so the limit covers the decoded copies
held in memory, not just the bytes read from storage. Pages are
content-addressed and checksum-verified when first read, so a cached page stays
valid for as long as it is cached.

Trace leaf references carry bounded ID blooms and complete service sets, so
exact-ID lookup can skip irrelevant leaves before reading them. Unknown,
legacy or over-budget summaries scan conservatively, and false positives consume
metadata budgets. This improves lookup but does not guarantee that any retained
window fits a query budget. Large batches and compaction outputs use a versioned
fixed 2 KiB ID bloom instead of a truncated ID-hash set. Mixed leaves combine
only identically sized canonical blooms; unknown/legacy sets always scan.

Each signal's own compaction grace affects its bucket-width window, together
with the shared retention deletion grace. Changing only trace compaction grace
does not resize or stop log/metric windows. Increasing the shared retention
grace can still exceed a scope's recorded width; keep these values stable after
activation and inspect capacity before changing them.

Expect more storage requests than without retention: inline entries are
periodically written out as pages, and cleanup issues list and delete requests.
Normal appends still cost one segment write plus one manifest write. Measure
request counts on your provider before production use; see
[storage costs](storage-costs.md).

Deletion throughput is bounded per node: by default at most 512 DELETE attempts
per 30 seconds, about 17 per second, for all tenants and all three signals together,
and lower if DELETE latency limits four concurrent requests. If ingest creates
segments faster than cleanup removes expired ones, the backlog grows. Watch
storage growth and the metrics below after enabling enforcement.

## Monitoring

The `/metrics` endpoint adds these node-local series, without tenant labels:

| Metric | Meaning |
| --- | --- |
| `pulse_retention_root_capacity_ratio` | Highest `capacity_ratio` among the retention-managed scopes cached on this node. |
| `pulse_retention_pending_buckets` | Expired buckets still being cleaned up, summed over cached managed scopes. |
| `pulse_retention_managed_scopes` | Retention-managed tenant/signal scopes cached on this node. |
| `pulse_detailed_operations_total{kind="retention"}` | Maintenance attempts by `operation` (`advance`, `cleanup`, `cleanup_retired`, `sweep`) and `outcome`, with a matching duration histogram. |

Object requests for manifest pages are counted with `purpose="metadata_page"`.
The gauges only cover scopes this node has loaded recently, so scrape every node
and take the maximum or sum across them. For a full picture of one tenant/signal,
use `inspect_policy/4`. Alert on a rising capacity ratio, on pending buckets that
keep growing, and on `error` outcomes for retention operations.

## Errors you may see

| Error | Meaning |
| --- | --- |
| `:retention_expired` | A record is older than the committed floor, or the write targets an expired bucket. |
| `:timestamp_too_new` | A record is further ahead than `PULSE_RETENTION_FUTURE_SKEW_MS`. |
| `:retention_capacity` | A manifest, page, bucket or per-request budget would be exceeded. |
| `:retention_policy_mismatch` | Configured and recorded durations differ, or `apply_policy` expected a different duration. |
| `:managed_manifest_missing` | The manifest of a retention-managed prefix is missing. Restore it; Pulse will not rebuild it. |
| `:retention_migration_required` | The tenant/signal still uses the old format in `enforce` mode; ingest resumes once the worker converts it. |
| `:metadata_scan_limit` | A query or maintenance operation needed more manifest pages or bytes than its budget allows. |
| `:invalid_catchup` | `start_catchup/4` was called on an unconverted prefix, while a job already exists, or with `from_ns` at or above the watermark. |

How the ingest receivers answer:

| Error | Remote write | Loki push | OTLP |
| --- | --- | --- | --- |
| `:retention_expired`, `:timestamp_too_new` | `400` | `400` | `400`, status code `3` (invalid argument) |
| `:retention_capacity`, `:metadata_scan_limit`, `:retention_policy_mismatch`, `:retention_migration_required` | `503` | `503` | `503`, status code `14` (unavailable) |
| `:managed_manifest_missing`, `:manifest_page_missing`, `:cas_retries_exhausted` | `503` | `503` | `503`, status code `14` |
| Any other storage error | `503` | `500` | `503`, status code `14` |

`400` responses are permanent: collectors drop those records instead of retrying
them. `503` is retried, so storage and retention failures are retried by all
three collectors' standard clients; Loki clients generally retry `500` as well.
Watch collector drop counters while switching to `enforce`.

### Availability during storage errors

- Queries against a retention-managed prefix fail instead of serving a stale
  manifest when the manifest cannot be refreshed, because cleanup may already
  have deleted what the stale copy references.
- Queries against a prefix in the old format keep serving the last manifest
  they loaded after a transport refresh failure, as before. A successfully
  fetched malformed or unsupported manifest instead fails the query and
  invalidates the cache; it is never hidden by an older readable root.
  Required-fresh alert reads invalidate an ordinary cached root after a decoded
  corruption error or confirmed root absence, even inside its freshness interval.
  They never reconstruct authority by LIST; managed prefixes remain fail-closed
  after invalidation. Transport errors alone do not erase a warm snapshot.
  For transport failures Pulse first checks the
  `.managed` marker: if it exists (another node converted the prefix), the query
  fails. If the marker check also fails, a node that enforces retention for that
  signal fails the query; other nodes, including those in `observe` or `paused`
  mode, serve the cached copy.
- A query that finds a data object or manifest page missing restarts once
  against a fresh manifest, then fails. A query whose own deadline passes while
  manifest pages are being read returns a timeout rather than a scan-limit error.
- Appends to a retention-managed prefix first refresh its manifest and fail
  if it cannot be read. On a node that enforces retention for the signal,
  appends to a prefix in the old format also load its manifest and are held
  with `:retention_migration_required` until it is converted. In `observe` or
  `paused` mode, appends to prefixes in the old format do not read the manifest
  beforehand.
- A node that has not loaded a prefix checks the `.managed` marker before the
  first upload, at most once per second. If that check fails, the append
  continues; the manifest owner checks the marker again before creating a
  manifest and fails closed, so an unreadable marker can at worst leave an
  unpublished data object behind, as any failed append can.

## Recovery and backups

Format-4 prefixes are covered by [manifest backups](configuration.md#manifest-backups):
the retention worker takes one every 15 minutes, and cleanup deletes an expired
object only after a backup records its retirement. A backup is a copy of the
format-4 root, including its floor; it costs one GET and one PUT however long
the history is.

For format 3: after conversion, the root manifest and the pages it references are the only
record of which objects are live, and the floor is irreversible.

- Back up or version the root **and** its pages together. A root restored without
  its pages, or a root older than the current floor, is not a valid recovery: it
  would reference deleted objects or re-expose expired data.
- If the manifest is lost, reads and writes return `:managed_manifest_missing`.
  Restore a coherent copy; do not delete the `.managed` marker to force a rebuild.
- Bucket versioning, soft delete and backups keep deleted bytes, billed and
  readable by anyone with bucket access, for as long as their own retention
  allows. Configure that separately.

## Limitations

- This is not a compliance or secure-erasure feature. Logically expired data
  stops being served immediately, but objects are deleted later, and copies in
  versions or backups are outside Pulse's control.
- An object can outlive its logical expiry: physical deletion happens roughly
  the retention duration plus the bucket width, future skew, grace period and
  cleanup lag after the object was written. A request whose records span the
  whole window can keep its oldest records for up to about twice the duration.
- No physical bound holds while retention is `paused`, the floor is not moving,
  cleanup cannot keep up, storage deletes keep failing, or uploads complete long
  after their request.
- One policy per signal applies to every tenant. Per-tenant durations are not
  supported.
- Manifests larger than 16 MiB are not converted automatically; they need
  `convert_offline/4` with ingest and compaction stopped for that prefix. In
  `enforce` mode they stay queryable but reject appends until converted.
- There is no log compaction; logs go straight from live to deleted.
