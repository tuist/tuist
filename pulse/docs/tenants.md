# Tenants and usage

Pulse can manage tenants at runtime and meter what each one uses, for
operators who run one shared deployment for many customers. Both features are
off by default and need the S3 storage backend.

- The **tenant registry** stores each tenant's state and credentials in the
  bucket. An admin API creates, suspends and deletes tenants without a
  redeploy, and deletion purges the tenant's data.
- **Usage metering** records, per tenant and hour, the ingest each instance
  acknowledged and the queries it ran. The admin API sums it for billing or
  capacity planning.

Both keep the bucket as the only authority, so they work with any number of
instances and with [separate pools](scaling.md#separate-pools).

## Admin API

The admin API is under `/api/v1/admin` and needs an admin Bearer token. Set
`PULSE_ADMIN_TOKENS` (chart `admin.tokenHashes`) to a JSON array of SHA-256
digests, in the same `sha256$<hex>` form as tenant tokens:

```sh
printf '%s' "$ADMIN_TOKEN" | shasum -a 256 | awk '{print "sha256$" $1}'
```

Without admin tokens every admin route answers `404`. A wrong or missing token
gets `401`. Serve the admin API only on a private network; it is routed with
the query role.

| Method and path | What it does |
| --- | --- |
| `GET /api/v1/admin/tenants?after=&limit=` | Registered tenant names in lexical order, at most `limit` (default 100, at most 1000), and a `next` cursor. |
| `GET /api/v1/admin/tenants/<tenant>` | The tenant's record: `state`, `token_count`, `created_at`, `updated_at`, and the deletion times when set. Token hashes are never returned. |
| `PUT /api/v1/admin/tenants/<tenant>` | Create or update a tenant. The JSON body may set `state` (`active` or `suspended`) and `token_hashes` (at most 8 `sha256$<hex>` digests). New tenants start `active`. |
| `DELETE /api/v1/admin/tenants/<tenant>` | Start deleting the tenant; answers `202`. Repeating it is harmless. |
| `GET /api/v1/admin/tenants/<tenant>/usage?start=&end=` | The tenant's usage, per hour and in total. See [usage metering](#usage-metering). |

Changes to a record are conditional writes, so concurrent admin calls on
different instances never lose an update; a call that keeps conflicting gets a
retryable `503`.

## Tenant registry

Enable it with `PULSE_TENANT_REGISTRY_ENABLED=true` (chart
`tenantRegistry.enabled`) on every instance.

### Credentials

A registered tenant authenticates with any token whose digest is in its
`token_hashes`, as a Bearer token or as the password of HTTP Basic credentials
whose username is the tenant. To rotate, add the new digest, move senders to
the new token, then remove the old digest. Pulse only stores digests: generate
tokens on your side and send their SHA-256 digests.

Tenants in `PULSE_TENANT_TOKENS` keep working without a record. A record's
state applies to them too, so you can suspend or delete a configured tenant
through the API. Its configured token stays valid while it is active.
With the registry enabled, `PULSE_TENANT_TOKENS` may be empty.

### States

| State | Effect |
| --- | --- |
| `active` | Ingest and queries work as usual. |
| `suspended` | Ingest, queries, MCP and Sentry ingestion answer `403`; data and background work stop changing but nothing is deleted. Set `active` to resume. |
| `deleting` | Refused like `suspended`. Its data is purged once the deletion grace period has passed. |
| `deleted` | Purged. The name stays reserved: it cannot be created again. |

Compaction, retention and alert evaluation skip tenants that are not active.
Reliability assessments and Sentry error projection are configured per tenant;
remove those bindings when you delete a tenant.

### Propagation and its bounds

Each instance caches tenant records for `PULSE_TENANT_REGISTRY_CACHE_TTL_MS`
(default 30 seconds), so a suspension or deletion is enforced everywhere within
that time. The instance that made the change applies it immediately.

A request naming a tenant the instance has not cached reads its record from the
bucket. Each instance does at most `PULSE_TENANT_REGISTRY_MAX_LOOKUPS_PER_SECOND`
(default 100) such reads; requests beyond that get a retryable `503`
(`auth_unavailable`) instead, so requests naming random tenants cannot cause
unbounded bucket reads. Cached tenants are unaffected, and an expired entry is
served until it can be refreshed. The cache holds at most 100,000 tenants per
instance.

If the bucket cannot be read and a tenant is not cached, its requests get a
retryable `503`.

### Deletion

`DELETE` marks the tenant `deleting` and writes a deletion marker under
`system/tenant-deletions/v1/`. Once `PULSE_TENANT_DELETION_GRACE_MS` (default
10 minutes) has passed, instances with the maintenance role delete every object
under `tenants/<tenant>/`: segments, manifests, metadata, alert rules and
reliability or error objects. Each pass, every `PULSE_TENANT_PURGE_INTERVAL_MS`
(default 60 seconds), deletes at most 5,000 objects. When nothing is left, the
tenant becomes `deleted` and the marker is removed. Progress shows in
`pulse_tenant_purged_objects_total`.

The grace period must be at least twice the cache TTL, and should exceed your
longest request, compaction and retention timeouts, so that no instance is
still writing for the tenant when the purge runs. Usage records are kept.

## Usage metering

Enable it with `PULSE_USAGE_ENABLED=true` (chart `usage.enabled`) on every
instance that serves ingest or queries. Each instance counts, per tenant and
UTC hour:

| Group | Fields |
| --- | --- |
| `logs`, `metrics`, `traces` | `requests` (acknowledged ingest requests), `bytes` (their declared `Content-Length`, or message size over gRPC), `records` (log lines, samples or spans stored) |
| `queries` | `requests` (queries admitted, whatever their outcome) and `duration_ms` (their wall time) |

Requests refused by admission, authentication or validation are not counted.
Records include those written by recording rules. Sentry events count as
`logs` records but not requests or bytes. Requests without `Content-Length`
add no bytes.

Every `PULSE_USAGE_FLUSH_INTERVAL_MS` (default 60 seconds), each instance writes
its cumulative totals for each tenant-hour it served to

```text
usage/v1/tenant=<tenant>/hour=<YYYY-MM-DDTHH>/<instance>.json
```

where `<instance>` is random per process start. Writing totals, not
increments, means a repeated or retried write never double-counts. Counts
accepted after an instance's last successful write are lost if it crashes, so
usage can be under-counted by at most one flush interval per crash, never
over-counted. Instances flush once more when they shut down cleanly.

Each flush writes one object per tenant that sent or queried since the last
flush, on each instance. Lowering the interval reduces what a crash can lose
but adds requests. Usage objects are outside `tenants/`, so they survive tenant
deletion; they are not covered by retention and grow by about one small object
per active tenant, hour and instance.

`GET /api/v1/admin/tenants/<tenant>/usage` sums every instance's objects.
`start` and `end` are RFC 3339 timestamps or Unix seconds, truncated to the
hour and both inclusive. The default is the 24 hours up to the current one;
ranges can span at most 31 days and 10,000 objects (`422` beyond that). The
response lists each hour with usage and a `total`:

```json
{
  "tenant": "acme",
  "start": "2026-11-03T00",
  "end": "2026-11-03T23",
  "hours": [{"hour": "2026-11-03T16", "traces": {"requests": 39, "bytes": 812345, "records": 6012}, "...": {}}],
  "total": {"logs": {"requests": 0, "bytes": 0, "records": 0}, "queries": {"requests": 4, "duration_ms": 310}, "...": {}}
}
```

The current hour keeps growing until it ends, and each instance's latest
counts arrive with its next flush.

## Not yet built

- Stored bytes per tenant. Use bucket inventory or provider metrics per
  `tenants/<tenant>/` prefix for now.
- Cluster-wide quotas: [per-tenant limits](scaling.md#per-tenant-limits)
  apply per instance.
- Per-tenant retention periods.
