# Parallel error collection in Pulse (disabled by default)

This is an opt-in secondary copy, not a backend cutover. Atlas's existing
ClickHouse buffer, issue coalescer, DSNs, native logger and HTTP responses are
unchanged. Grafana workloads, agents, metrics, logs and traces are unchanged.
No historical events are backfilled.

## Failure isolation and delivery contract

After primary Atlas capture, the shared recorder offers a copy to a fixed-slot
ETS queue. There is **no Pulse network request, GenServer call/cast or database
write** on the client path. Disabled/unmapped sources do no serialization work.
When full, admission drops the secondary copy before scrubbing/encoding it.
Other admission failures cannot change the primary return value. Scrubbing adds
bounded CPU work for admitted sources; this is not physical process/host isolation.

Each Atlas replica has 64 slots, including the in-flight copy and retries, with
at most 128 KiB source JSON and 128 KiB scrubbed JSON per event. Thus queued
payloads total at most 8 MiB per replica, plus bounded routing, ETS and transient
sender/producer overhead. Source JSON over the cap or deeper than 32 levels is
not mirrored. Producer concurrency still follows Atlas request concurrency;
the mirror creates no producer tasks or payload-bearing mailbox backlog.

One sender uses a separate Finch instance with size-one pools per configured
origin (at most 256), and at most one active background request task. Requests
have a two-second wall-clock deadline, no redirects or automatic
HTTP retries, and discard response bodies. Transport failures, HTTP 408, 429 and
5xx retry after one then five seconds, at most three attempts total. Other
statuses drop immediately. Pending copies expire after 60 seconds; expiry is
checked by the sender, so physical reclamation can lag one in-flight deadline.
Retry-After is not a durable scheduling promise; this intentionally small retry
budget yields to capacity/expiry drops during a prolonged outage.

Pending state is **volatile**. Restart, worker crash, shutdown, saturation,
permanent rejection, retry exhaustion and expiry lose mirror copies. There is
no shutdown flush, replay log, durable checkpoint or exactly-once guarantee.
Atlas acceptance is not proof that either backend has durably stored an event.
This is appropriate for an experimental parallel backend, not guaranteed capture.
Both optional children are temporary: unexpected worker or Finch termination
cannot consume Atlas's supervisor restart budget. Worker loss disables admission;
Finch loss makes delivery fail within the same bounded retry/drop policy.
Restore mirroring with an application restart, not a background restart loop.

Every attempt keeps the Atlas-normalized event ID and occurrence timestamp and
the exact same scrubbed bytes. Pulse only acknowledges after its existing
segment/manifest publication. A lost success can therefore produce duplicate
raw log rows; Pulse's error queries deduplicate project/event IDs, not raw logs.
SDK resubmissions with the same ID likewise remain the same error identity.
Do not interpret raw LogQL counts as unique errors or compare Pulse grouping
directly with Atlas issue IDs.

The existing Atlas buffer's fire-and-forget casts do not bound its mailbox.
Oban insertion would add a database round trip on the primary capture path, and
an ordinary outbox would accumulate copies during an outage without separate
admission/expiry machinery. Neither is reused as the mirror queue. The existing
Req/Finch transport and Pulse authenticated Sentry publication are reused.
As reference evidence, Sentry Elixir **13.1.0** (Atlas's locked SDK) uses async
sender casts and a shared queued-event counter in
[`Sender`](https://github.com/getsentry/sentry-elixir/blob/v13.1.0/lib/sentry/transport/sender.ex)
and [`SenderPool`](https://github.com/getsentry/sentry-elixir/blob/v13.1.0/lib/sentry/transport/sender_pool.ex).
The mirror instead requires atomic slot admission before retaining a copy and
bounds bytes as well as count. It does not change the SDK transport globally.

`Atlas.Engineering.Errors.PulseMirror.stats/0` returns node-local fixed counters:
`delivered`, `retried`, `full`, `expired`, `rejected`, `failed`. Restart resets
them. They contain no tenant/project labels, event samples, keys, response bodies
or arbitrary error strings. Mirror failures generate no error log feedback loop.
These counters are inspection diagnostics, not an installed Grafana alert.

## Configuration and attribution

Leave `ATLAS_PULSE_ERROR_ROUTES_JSON` unset to preserve the current deployment.
Demo and ClickHouse-disabled instances never start the mirror. For an approved
deployment, supply a JSON array of 1–256 exact routes in Atlas's application
configuration; invalid/duplicate sources fail mirror startup:

```json
[
  {
    "atlas_project_id": "00000000-0000-4000-8000-000000000001",
    "atlas_domain_id": null,
    "pulse_project_id": "900001",
    "url": "https://approved-pulse-ingest.example.com",
    "public_key": "provision-an-ingest-only-key"
  }
]
```

This example is not a production identity, credential or activation instruction.
`url` is an operator-controlled HTTP(S) origin of at most 2,048 bytes without userinfo/path/query; use
TLS in production and restrict egress to the approved receiver. `public_key`
permits 1–256 ASCII alphanumeric, underscore or hyphen characters. The sender
constructs `POST /api/<pulse_project_id>/store/` with `X-Sentry-Auth`. Keys are
server-side configuration, never taken from incoming SDK events or credentials.

Null/omitted `atlas_domain_id` matches **only** project-level capture, including
the native self-project. Domain-scoped SDK events need their own exact route;
there is no project fallback, wildcard or automatic project discovery. Prefer a
distinct Pulse project/key for each Atlas project/domain pair so diagnostic
grouping and query filters preserve that boundary. The scrubbed event also has
authoritative `atlas_project_id` and nullable `atlas_domain_id` fields overwritten
from primary capture, never from payload claims.

Provision each destination in Pulse's existing `sentry.projects` configuration
with its fixed tenant, service and SHA-256 public-key digest. Incoming Atlas
credentials still authorize only Atlas's existing project/domain. Neither SDK
payload project/tenant fields nor tenant headers choose the Pulse destination;
the Pulse key/project configuration alone controls tenant/service attribution.
Use independent ingest-only keys, never query bearer tokens. Existing Pulse
ingress exposes only `/mcp`; expose only the explicitly approved project-scoped
POST store routes (or an appropriately private authenticated path), with rate
limits and credential/query redaction. No ingest exposure is added here.

## Privacy and approval gate

Before queue retention or transport, recursively replace user/request/header
objects, legacy Sentry User/Http interfaces and named credentials with
`[Filtered]`, including tag key/value pairs. Raw Atlas storage is unchanged.
Messages, exception text, stack/source context, breadcrumbs, URLs, tags and
arbitrary extras can still contain PII; this is not general PII detection. Keep
upstream SDK scrubbing and `send_default_pii=false`, review the actual sources,
and treat Pulse event text as untrusted. See both affected data-export inventories.

**No production data sharing is authorized or enabled by this change.** Proposed
initial approval scope: new errors captured under Atlas's private self-project,
project-level only (native LoggerHandler plus any SDK envelopes authorized to
that same project), to one new dedicated Pulse numeric project, tenant and
`atlas` service; no other projects/domains, history, metrics, logs or traces.
The operator must supply/approve the actual Atlas UUID, unused Pulse numeric ID,
tenant/read audience, endpoint, retention, region and key ownership before
activation. Broader SDK collection requires an explicit list of additional
project/domain → Pulse project/tenant/service mappings and a privacy review.

After approval, an authorized operator provisions the ingest-only key and digest,
adds the approved Pulse project map and narrow ingress/egress, and configures
the corresponding Atlas routes; restart serving instances consistently. Confirm
an approved synthetic event in Atlas and Pulse, counters and failure isolation.
Disable by removing Atlas routes and restarting; queued copies are discarded,
but already-published Pulse objects remain subject to Pulse retention/erasure.
No Secrets, elevated cluster access or deployment actions are needed to review
or test this implementation.
