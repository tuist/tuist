# Error tracking

Pulse accepts Sentry SDK **JSON error events** and exposes them to agents through
`query_errors` and `list_error_issues`. This is an experimental error-tracking
subset, not a replacement for every Sentry service. No SQL database, queue,
accounts service, or persistent local disk is required.

## Configure a project and SDK

Provision a numeric project ID, a tenant, a service name, and one or more public
key digests. Projects are deployment configuration, not mutable API resources.
The default empty configuration rejects all Sentry ingestion, even in development.

```sh
PUBLIC_KEY=$(openssl rand -hex 16)
DIGEST=$(printf '%s' "$PUBLIC_KEY" | sha256sum | cut -d' ' -f1)
export PULSE_SENTRY_PROJECTS_JSON="{\"42\":{\"tenant\":\"production\",\"service\":\"api\",\"public_key_hashes\":[\"$DIGEST\"]}}"
```

Set the SDK DSN to `https://<PUBLIC_KEY>@errors.example.com/42`. For example:

```python
import sentry_sdk

sentry_sdk.init(
    dsn="https://<PUBLIC_KEY>@errors.example.com/42",
    send_default_pii=False,
    traces_sample_rate=0,
    auto_session_tracking=False,
)
```

Use your deployment's HTTPS hostname, not sentry.io. Disable profiling, replay,
sessions, attachments and performance collection in each SDK. Existing stack
frames, exception chains, breadcrumbs, tags, release, environment, SDK metadata
and trace/span identifiers are retained as part of the event, subject to scrubbing
and budgets. Native crash minidumps are not JSON events and are unsupported.

`PULSE_SENTRY_PROJECTS_JSON` is a JSON object with at most 256 projects. IDs are
1–32 decimal digits. Each object requires `tenant`, `service` and
`public_key_hashes`; tenant/service use 1–128 letters, digits, `_`, `.` or `-`.
There must be 1–8 lowercase SHA-256 hex digests per project. Invalid configuration
stops startup. Give a project its own key; sharing a key intentionally permits
ingestion into every project with that key. Rotate by adding the new digest,
restarting all nodes, updating SDKs, then removing the old digest and restarting.
Keep project IDs bound to the same tenant/service across deployments. Changing
the mapping changes attribution for future events, not stored records; do not
reassign IDs or reuse old DSNs across tenant trust boundaries.

Optionally set `allowed_domains` per project to restrict browser ingestion on
store, pixel and envelope routes. Omission preserves unrestricted origins;
`[]` denies all requests carrying an Origin header. Requests without Origin
remain accepted with valid credentials, including with an empty list.
Allow at most 32 nonempty UTF-8 patterns, each at most 256 bytes. Examples:
`["https://app.example.com", "https://*.example.com:8443"]`. Components compare
case-insensitively; omitted scheme/port or a whole `*` component is unrestricted.
A leading domain `*` matches the root or subdomains only on a label boundary;
other embedded stars are literal. Bracketed IPv6 is supported. Pattern paths
are ignored and explicit ports compare literally, without default-port inference.
With this option set, Origin must be a single HTTP(S) origin of at most 2048
bytes, without credentials, path, query or fragment; opaque/malformed origins
reject with `403`. These grammar bounds and the rejection status are local
policies, not full Relay origin-parser parity. Origin never replaces a key or
resolves an ambiguous project-less key. This is a browser restriction, not
authentication: non-browser clients can omit or forge the header. Restart all
serving instances after changing the project map so restrictions agree.

The Helm chart accepts this map as `sentry.projects`. Its ingress does **not**
expose SDK paths by default. Add an exact path for each enabled endpoint, alongside
any existing routes you need:

```yaml
sentry:
  projects:
    "42":
      tenant: production
      service: api
      public_key_hashes: ["<64 lowercase SHA-256 hex characters>"]
ingress:
  paths:
    - path: /api/42/envelope/
      pathType: Exact
    - path: /api/42/store/
      pathType: Exact
    # Optional, for legacy clients without a project in their URL.
    - path: /api/store/
      pathType: Exact
    - path: /mcp
      pathType: Exact
```

## Receiver contract

- `POST /api/<project>/envelope/`: byte-framed Sentry envelopes, including an
  optional final newline and length-delimited multiline/binary items. At most one
  `event` item. Empty envelopes are valid.
- `POST /api/<project>/store/`: JSON error events, including legacy base64 JSON
  and base64-wrapped zlib bodies without a `Content-Encoding` header. Legacy
  decoding runs after authentication and any HTTP decompression; its decoded
  event is limited to 1 MiB before JSON parsing. Zlib must be one complete,
  checksummed stream. Raw unwrapped zlib, raw DEFLATE, gzip inside base64 and
  recursive base64 reject. Base64 envelope framing is not supported.
  An exact `Content-Type: application/x-sentry-envelope` instead selects the
  bounded envelope decoder, with the same event/item/body ceilings and discard
  reporting as `/envelope/`. This is a raw, case-sensitive match; media-type
  parameters do not select it. Store still requires credentials in the request
  header/query, even when the envelope contains a DSN. Supplied DSN credentials
  must also agree with the request. Use the JSON media type for a JSON event:
  a lone JSON object under the envelope media type is a header-only envelope,
  returning `id: null` without storing an event. Upgrade ingress applications
  consistently before sending envelopes to store URLs.
- `POST /api/store/`: the same store receiver for legacy clients whose URL has
  no project ID. The presented key must match exactly one configured project;
  missing, unknown or ambiguous keys return `403`. Key rotation aliases within
  one project are supported. Payload `project`, query `project_id` and tenant
  headers cannot choose the project. Prefer project-scoped URLs when projects
  share a key; those URLs continue to authenticate only their named project.
  Envelope POSTs can use a uniquely resolving request credential without a DSN;
  an envelope DSN cannot bind to a project-less URL and rejects.
- `GET /api/<project>/store/` and `GET /api/store/`: legacy pixel ingestion.
  URL-encode the JSON event or its base64/base64-zlib representation in
  `sentry_data`, with the same configured credentials and project-binding rules.
  After durable publication, the response is a 1×1 `image/gif` with
  `Cache-Control: no-store`, not a JSON event ID. Invalid requests and storage
  failures return error statuses, never a successful pixel. `HEAD` probes return
  `405` without publication; envelope GET ingestion is not supported.
  **Prefer POST:** URLs can expose unscrubbed event data in proxy, access or
  security logs before Pulse's payload scrubbing. Omit query strings from such
  logs and do not cache ingestion responses.
- POST bodies accept identity, gzip, zlib-wrapped `deflate` and `zstd` encoding;
  other encodings return `415`. Deflate requires one complete stream with a
  valid checksum; raw DEFLATE, trailing bytes and concatenated streams reject.
  Zstd requires one complete standard frame without a preset dictionary and a
  window no larger than 16 MiB; checksums, when present, must validate.
  Truncated, trailing, concatenated and skippable frames reject with `400`;
  oversized windows or expanded bodies return `413`.
  An omitted or single empty `Content-Encoding` value means identity, not gzip
  auto-detection. Brotli and stacked encodings remain unsupported.
  Envelope requests may use the standard SDK media type, no content type, or
  browser simple-request media types. Browser ingestion supports `OPTIONS` and
  wildcard, credential-free CORS. Preflight advertises `POST` only and permits
  `Content-Encoding` for compressed requests, alongside `Content-Type`,
  `Authorization`, `X-Sentry-Auth`, `sentry-trace` and `baggage`. Ingestion
  responses include `Cross-Origin-Resource-Policy: cross-origin`, including
  preflight and rejected requests. This does not enable cookie authentication;
  reads do not inherit these policies.
- Credentials may be `X-Sentry-Auth: Sentry sentry_key=<PUBLIC_KEY>, sentry_version=7`,
  the same Sentry scheme in `Authorization`, query parameter `sentry_key`, or
  (on `/envelope/`) the envelope header's `dsn`. The Sentry scheme is
  case-insensitive in either header; field names remain case-sensitive.
  When multiple forms are present, keys must agree and the DSN project must match
  the URL.
  An exactly empty `X-Sentry-Auth` value is treated as absent; a valid query key
  or envelope DSN is still required. Nonempty malformed headers remain invalid.
  Unknown projects/keys and missing or inconsistent credentials return `403`.
  Other `Authorization` schemes do not supply a Sentry key: tenant bearer tokens
  cannot ingest Sentry events, and Sentry keys cannot authorize reads. HTTP Basic
  authentication on Sentry routes is not supported. Upgrade all Sentry-serving
  apps before relying on the alternate header or mixed-case scheme spelling.
- Credential configuration, not payload fields or `X-Scope-OrgID`, determines
  tenant and service. Public DSN keys allow **ingestion only**, never queries.
  With a [trusted issuer](issuer-credentials.md#status-list), projects can also
  come from its signed status list; `PULSE_SENTRY_PROJECTS_JSON` wins for the
  same project ID. Keys sent in `X-Sentry-Auth`, `Authorization: Sentry` or
  `sentry_key` are checked before the body is read.
- Successful POST responses use `200` with `{"id":"<event ID>","discarded_items":{}}`.
  Both POST success and a pixel GET's `200` follow durable event publication:
  Parquet segment PUT and conditional manifest publication. Storage
  failure returns `503` with `Retry-After: 5`, never local acceptance. This is a
  truthful negative acknowledgment, **not a guarantee of SDK redelivery**.
  Stock Python 2.72.0 and Node 11.8.0 SDKs did not replay failed `503` uploads in
  compatibility checks. SDK queues can drop events on failure, shutdown or rate
  limiting. Changing the response to `429` would not provide durable capture;
  applications needing that guarantee must own a durable upstream transport.
- Non-event items are discarded, including transactions, sessions, attachments,
  profiles, replays and client reports. Responses report counts by item type in
  `discarded_items`, plus total `X-Pulse-Discarded-Items` when nonzero. An
  unsupported-only envelope returns `200` with `id: null` and stores nothing.
  SDKs may ignore this diagnostic; disable unsupported collection explicitly.
- Malformed events/framing, invalid IDs/fingerprints and invalid timestamps return
  `400`, with no append. Envelope event IDs take precedence over payload IDs;
  32-hex, canonical dashed UUIDs, `{dashed-UUID}` and `urn:uuid:dashed-UUID`
  normalize to lowercase hex. Hexadecimal digits and the URN prefix are
  case-insensitive. Wrappers require the exact dashed `8-4-4-4-12` form;
  nested wrappers, whitespace and wrappers around undashed IDs reject.
  Missing IDs are generated, so clients without stable IDs cannot deduplicate
  retries. Upgrade all ingress instances for consistent wrapper acceptance;
  existing accepted IDs, storage formats and retry bytes are unchanged.
- Newly ingested events project Sentry level aliases `log` → `info` and
  `critical` → `fatal`, and integer Python levels 10/20/30/40/50 →
  `debug`/`info`/`warning`/`error`/`fatal`, into log severity text and numbers.
  The original event's `level` remains unchanged. Unknown nonempty string levels
  retain their text with error severity; missing or other unsupported values
  retain the existing error fallback. This is not full event normalization.
  Upgrade all Sentry-serving instances for consistent projection; stored history
  is not rewritten and no storage migration is required.
- Environment filters also recognize legacy `tags.environment` (object tags or
  ordered key/value pairs) when the top-level environment is absent, empty or
  non-string. A nonempty top-level string wins; otherwise the first matching
  tag owns the projection, even when empty or null. Tag scalar values use the
  release scalar conversion below, then trim surrounding whitespace. The raw
  scrubbed event and tags remain unchanged. This is not full Relay tag or
  environment validation. Upgrade all Sentry-serving instances for consistent
  new-event filtering; existing stored projections are not repaired. No storage
  migration or issue-ID change is required.
- Release filters use scalar normalization: strings stay unchanged, booleans
  become `True`/`False`, signed-int64/unsigned-uint64 integers become decimal
  strings, and floats strictly inside ±2⁵³ truncate toward zero (including
  `-0`). Null, containers and out-of-precision floats project an empty release.
  The scrubbed event keeps its original release type/value. Upgrade all
  Sentry-serving instances for consistent filtering of new events; previously
  stored empty release projections are not repaired. Issue IDs and existing
  string releases are unchanged. No storage-format migration is required.
- Timestamps accept Unix seconds or ISO-8601. Floating-point Unix seconds round
  to the nearest microsecond, including carry into the next second; the raw event
  value is preserved. Integer seconds remain exact. Upgrade all Sentry-serving
  instances for consistent new-event timestamps; stored history is not rewritten.
  Offset-free date-times mean UTC,
  not the node's local timezone; malformed dates/offsets still reject. Times
  must be nonnegative signed-64-bit nanoseconds and cannot exceed the node clock
  by ten minutes. Missing timestamps use receipt time. No clock-drift correction
  is applied. Log retention can independently reject expired/future records
  with `400`, including legacy events with old source timestamps.
- Limits: 4 MiB wire body, 16 MiB expanded gzip/deflate/zstd body, 1 MiB per event,
  100 envelope items and 16 KiB per envelope/item header. Event structure follows the shared
  `PULSE_INGEST_MAX_DEPTH`, `MAX_NODES`, `MAX_ATTRIBUTES` and `MAX_KEY_BYTES`
  budgets; event string/aggregate bytes are capped at 1 MiB. Fingerprints contain
  at most 32 supplied components, with strings capped at 256 bytes each.
  Oversized bodies/events/items/structure return `413`. Pixel query strings retain the existing 1,000,000-byte application
  ceiling (`414` above it); decoded/inflated events still cap at 1 MiB. HTTP
  servers and proxies can impose lower URL limits; the default HTTP/1 request
  line limit is 10,000 bytes. These are request safety limits,
  **not per-key rate limiting**.

## Query errors and issue groups

Use the normal tenant bearer token with `POST /mcp`; DSN credentials do not grant
read access. Both read-only tools require `tenant`, `start_ts_ns`, `end_ts_ns`
(inclusive Unix nanoseconds). Optional exact filters: `project`, `service`,
`environment`, `release`, `issue_id`, `event_id`. `limit` defaults to 100 and
accepts 1–5,000 per page. An optional opaque `cursor` continues a page.

```json
{
  "name": "list_error_issues",
  "arguments": {
    "tenant": "production",
    "project": "42",
    "environment": "production",
    "start_ts_ns": 1767225600000000000,
    "end_ts_ns": 1767312000000000000,
    "limit": 20
  }
}
```

This is the `tools/call` body inside the normal MCP request; see
[querying](querying.md) for protocol headers and metadata.

- `query_errors` returns newest-first events with their scrubbed payload, project,
  service, issue/event IDs, occurrence/receipt timestamps, trace ID and span ID.
  Pass `issue_id` to inspect examples, or `event_id` for an individual event.
- `list_error_issues` returns stable issue IDs, latest title/service/event ID,
  occurrence count, and first/last seen **inside the selected window and filters**.
  It does not claim lifetime counts, global first seen or a resolved/ignored status.
- Responses include `results`, `matched_events` (unique project/event IDs in
  the filtered window), `matched_results`, `snapshot_id` and `next_cursor`.
  Results are paginated only after counting/grouping. Pass `next_cursor` as
  `cursor` with the same tool, tenant, time window and filters; `null` means the
  last page. `limit` may change between pages. Each JSON text page is at most
  2 MiB, so large events can produce fewer results than `limit`.
  Retried IDs count once within that window; conflicting copies prefer the latest
  occurrence time, then a deterministic payload tie-breaker. Raw log queries
  still expose all ingestion attempts. Storage is at least once; no durable
  event-ID uniqueness registry is maintained.
- Cursors are authenticated, expire after ten minutes, and require a shared
  `SECRET_KEY_BASE` across nodes. Each page freshly rescans the same bounded
  window and checks its result digest; it does not pin objects against retention.
  Late arrivals, changed retained results, expired/tampered cursors or a changed
  query scope return `error_query_reset_required`. Restart from the first page;
  use a fixed historical window to reduce resets. Rotating `SECRET_KEY_BASE`
  invalidates outstanding cursors. This cursor is **not a monitoring checkpoint**.
- Queries run in the existing supervised, heap/concurrency/deadline/scan-bounded
  runner. More than 5,000 matching stored occurrences, including retries, returns
  an error rather than partial counts—even with a small result limit. Narrow the
  window or filters. This is a bounded scan, not an indexed hyperscale issue store.
- S3 diagnosis scans also have a separate **32 MiB decoded-column budget** across
  the whole window, including work repeated after a missing-object retry. Small
  compressed objects can expand far beyond their stored size. Expanded string
  lengths are preflighted before Arrow materialization, including ordinary log
  rows in legacy or mixed segments that exceed the Sentry event-size cap. All
  decoded column buffers count, including rows later rejected inside a mixed
  batch; oversized selected row groups are rejected before expansion. Exhaustion
  returns `query_decoded_limit`, never partial results. A 2 MiB output page or `limit: 1`
  does not reduce the work needed for exact whole-window counts and grouping.

Issue grouping is versioned (`v1_` plus SHA-256) and project-scoped. It uses the
last exception's type and last in-app frame's module/filename and function,
falling back to the last frame. Without a usable frame it uses exception type,
logger and a bounded message with digit runs/hex addresses normalized. SDK custom
fingerprints override grouping; `{{ default }}` expands default components.
JSON-framed components prevent delimiter collisions. This is **Pulse grouping**,
not byte-for-byte Sentry or Atlas grouping compatibility.

Fingerprint arrays accept strings, booleans (`True`/`False`), signed-int64 or
unsigned-uint64 integers, and floats with absolute value strictly below 2⁵³.
Floats truncate toward zero, preserving a negative-zero component as `-0`.
Null components are ignored; an empty effective fingerprint uses default grouping.
Only grouping components are converted: the scrubbed event keeps its original
fingerprint values. At most 32 supplied components and 256 bytes per string
are accepted. Malformed components and out-of-range numbers reject the whole
event, rather than silently falling back to another group. Upgrade all
Sentry-serving applications for consistent admission; existing issue IDs and
accepted string-fingerprint identities are unchanged. No storage migration.

Exception containers may be a `{"values":[...]}` object, a direct array or a
single exception object. Titles and new-event grouping select the last exception
consistently across these forms; the scrubbed event retains its original shape.
Upgrade all Sentry-serving applications for consistent grouping of new events.
Previously stored issue IDs are not rewritten or merged: old array/single-object
events can remain in their former fallback groups, even though raw retained-window
issue titles now recognize their exception details. Existing wrapped-event identities are
unchanged. This does not normalize other Sentry container fields.

A nonempty string `logentry` supplies the same title and new-event grouping
message as `{"formatted":"..."}`. Exception values still take precedence,
and the scrubbed event retains the original string. Upgrade Sentry-serving
applications consistently; existing issue IDs are not rewritten or merged.
This does not interpolate log parameters or implement full Relay normalization.

Non-object `logentry`, legacy `message` and `sentry.interfaces.Message` values
also supply JSON display text for numbers, `true` and arrays. Literal `false`
and null remain absent; objects still require string `formatted`/`message`
fields. Rendering follows scrubbing and preserves the original event values,
exception precedence and the 500-character title bound. Numeric text uses
Pulse's JSON encoder, not complete Relay float-format parity. Upgrade query and
ingress apps together: new default groups can change, but retained issue IDs
and materialized summaries are not migrated. Storage/native formats are unchanged.

Legacy top-level `message` objects also use their string `message` field when
`formatted` is absent or null, rather than falling back to `Error`. Explicit
`logentry` and exception values retain precedence, and empty formatted strings
remain empty. Scrubbed event shapes and custom fingerprints stay unchanged.
Upgrade Sentry-serving applications consistently for new default groups;
retained issue IDs and materialized summaries are not migrated. The existing
500-character title limit still applies, without parameter interpolation or
any storage-format/native change.

The exact legacy names `sentry.interfaces.Message` and
`sentry.interfaces.Exception` also supply logentry and exception details for
titles and new default groups. A present canonical `logentry` or `exception`
field takes priority over its alias, even when null or malformed; similarly
prefixed or differently cased names are not aliases. Original scrubbed event
shapes and custom fingerprints stay unchanged. Upgrade query and ingress
applications together: raw retained-window titles can improve, but old stored
issue IDs and materialized summaries are not rewritten or merged. This does
not add general alias normalization, parameter interpolation or a native/
storage-format change.

Within an exception, `sentry.interfaces.Stacktrace` supplies frame-based default
grouping when `stacktrace` is absent. A present canonical field wins even when
null, malformed or empty; similarly named fields are not aliases. Original
scrubbed exceptions and literal custom fingerprints stay unchanged; `{{default}}`
fingerprint components use the frame-based default. Upgrade
ingress applications consistently: new legacy-stacktrace events can get different
issue IDs, while retained issue IDs and materialized summaries are not rewritten
or merged. This does not add top-level event-stacktrace grouping or symbolication.

Non-string exception `value` fields supply compact JSON text for issue titles
and new-event default grouping instead of disappearing into the fallback
message. Object keys sort lexically, including nested objects; strings remain
literal and null retains the existing fallback. Conversion happens after
scrubbing, so filtered credentials cannot reappear in a title. Original scrubbed
event types and custom fingerprints remain unchanged, with the same 500-character
title bound. Numeric rendering uses Pulse's JSON encoder, not a claim of complete
Relay float-format parity. Upgrade all Sentry-serving applications consistently:
new default groups can differ for these values, while previously stored issue
IDs and already-materialized index summaries are not rewritten or merged.
No storage-format or native upgrade is required.

Events also work with existing LogQL, for example
`{error_source="sentry", error_project="42", environment="production"}`.
Their trace/span IDs support correlation with other logs. LogQL counts raw
attempts rather than deduplicated errors.

For new events, `contexts.trace.trace_id` accepts either 32 hexadecimal digits
or a canonical dashed UUID (`8-4-4-4-12` digits), case-insensitively. Correlation
fields store lowercase, undashed IDs; the original scrubbed context is preserved.
Span IDs still require exactly 16 hexadecimal digits. Invalid optional correlation
IDs produce absent correlation fields rather than rejecting the event; this is
separate from validation of the event's own `event_id`. Upgrade ingress
applications consistently. Previously stored absent correlation IDs are not
backfilled, and issue grouping, resource ceilings and storage formats do not change.

## Storage, privacy and limits

Errors are structured logs in the existing `signal=logs` Parquet segments and
manifest. Project, issue/event IDs, environment and release are resource labels;
service/time pruning and Rust row filtering reuse the existing storage path.
New segments also summarize complete, bounded `error_source` and `error_project`
sets so exact mismatches prune before scan budgets. Missing, invalid or
over-budget summaries are unknown and must scan; mixed segments still consume
their full row/byte budget. Existing segments are not retroactively summarized.
Error queries require a fresh committed manifest: refresh failures or missing
manifests fail explicitly rather than serving stale data or discovering objects
by listing the bucket.

Only well-formed structured error rows participate in error queries and the
monitoring index. Ordinary Loki/OTLP logs claiming Sentry resource labels but
missing valid event/issue IDs, a matching event object, or the required typed
fields are ignored by these error surfaces. They remain available through raw
log queries and still consume candidate, row and byte scan budgets. Resource
labels alone are not proof that a row came through the Sentry receiver.

No second event publication authority is introduced. Any node can ingest/query
after a restart without recovering local issue state. Run multiple instances
against the same bucket and project configuration: each acknowledges only its
successful shared manifest publication; no sticky routing or singleton ingest
process is required. Share `SECRET_KEY_BASE` for cross-instance cursors. Error
retention is **log retention**, unlimited by default; there is no separate error
policy or event deletion API. Use Pulse's coordinated retention, not independent
bucket lifecycle deletion of live segments.

Before persistence, Pulse removes entire `user`, `request` and `headers` fields
and the legacy `sentry.interfaces.User` / `sentry.interfaces.Http` equivalents.
These exact interface names are matched case-insensitively, including nested
objects; similarly prefixed arbitrary names are not interface aliases.
Common named credentials such as authorization, cookie, password, secret,
token, API keys and DSNs are recursively filtered. This is a conservative baseline, not
general PII detection: exception messages, URLs, source context, breadcrumbs,
tags and arbitrary `extra` strings can still contain sensitive information.
Configure SDK `before_send` scrubbing and keep `send_default_pii` disabled.
Queries and agent responses contain untrusted application text; do not treat
payload text as agent instructions.

Upgrade all Sentry-serving applications consistently to apply legacy-interface
scrubbing before new writes and derived titles. This change does not scrub
already-retained objects, backups or materialized evidence, and does not rewrite
stored issue identities. If legacy interface payloads were previously sent,
treat retained copies as potentially sensitive under your existing access and
retention policy. No storage-format/native change or automatic cleanup occurs.

DSN public keys ship to browsers and are not strong secrets. Restrict exposed
paths, rate-limit at ingress, and redact `sentry_key`, DSNs and auth headers from
proxy/access logs. Keep query bearer tokens server-side. Authorization is tenant
wide; projects within a tenant do not have separate read permissions.

These tools provide bounded ad hoc diagnosis, not reliable new-issue detection
or a durable issue-change feed. Polling window-scoped summaries can miss late
events or events that expire between polls. Separately enabling the experimental
[error monitoring index](error-monitoring.md) adds retained-history novelty,
replayable changes and explicit gap/reset reporting. It does not gate ingestion,
provide a latency guarantee, or deliver notifications. Paginating diagnosis
alone does not supply a monitoring checkpoint.

Not implemented in this diagnosis slice: issue resolve/ignore/reopen lifecycle, notification delivery,
symbolication, source maps, native minidumps, attachments, Sentry REST issue API,
performance/session/replay storage, or cross-signal automatic correlation.
Agents can query errors and poll the optional index; durable scheduling and
cursor persistence belong to the agent runtime, and infrastructure remediation
belongs to the separate remediation server.
