# Scaling

Every Pulse instance can accept any authorized ingest request and serve any
query, because the bucket is the only authority: manifests are published with
conditional writes, and local buffers, caches and counters are disposable. You
scale by running more instances, and you can add or remove them at any time.

## Size each instance by its memory limit

Each instance bounds its own memory with admission slots. It derives them from
its container memory limit (or `PULSE_MEMORY_BUDGET_MB`): ingest slots at about
32 MiB each, interactive query slots with a heap ceiling each, and a fixed
reserve. See [node memory envelope](configuration.md#node-memory-envelope) for
the formula and overrides. Requests beyond the slots are refused with retryable
overload errors (HTTP `429` with `Retry-After`, gRPC `RESOURCE_EXHAUSTED`, or the
query error `query_overloaded`). Grafana Alloy, the OpenTelemetry Collector and
Prometheus retry those, so an overloaded instance slows senders down instead of
being OOM-killed.

Two things are not covered by the slots:

- **Flat manifests.** A flat manifest (`PULSE_MANIFEST_FORMAT=flat`) grows with
  every append, at about 2 KiB of node memory per segment (see
  [memory breakdown](#memory-breakdown)). Paged and retention-managed manifests
  stay bounded.
- **Native query memory outside the heap**, such as decoded segments and
  accumulators. Each is bounded per query, not per node.

## Memory breakdown

`/metrics` breaks node memory down so you can see where it goes and catch
growth early:

- `pulse_memory_bytes{kind}`: `processes`, `binary`, `ets`, `code`, `atom` and
  `system_other` add up to `total`, the BEAM's own view
  (`pulse_vm_memory_bytes`). `beam_allocated` is what its allocators hold in
  carriers, `beam_allocator_free` the part of that holding no live data, and
  `beam_mapped` everything the BEAM has mapped. `native_codec`,
  `native_object_store` and `native_grpc` are the live Rust heaps of the native
  libraries; `malloc_in_use` and `malloc_free` are the C allocator's view.
  `rss` and `rss_anon` are what the operating system (and `kubectl top`) count.
- `pulse_memory_process_bytes{group}`: process heaps by role
  (`manifest_owner`, `append_buffer`, `ingest_flush`, `query`, `maintenance`,
  `http_connection`, `other`).
- `pulse_memory_ets_bytes{table}`: ETS tables by name.

Measured on one node with paged manifests referencing about 100,000 segments,
Alloy-like traffic of a few requests per second per signal, coalescing on and a
query round every 30 seconds, memory stayed flat for 40 minutes:

| Part | Mean | Scales with |
| --- | --- | --- |
| Code, atoms and literals | 55 MiB | release |
| Manifest owners (paged roots) | 5 MiB | recent segments, not history |
| Ingest buffers, flushes and connections | 10 MiB | request rate and size |
| Running queries | 0 to 10 MiB each here | query size, up to the query heap ceiling |
| Referenced binaries | 20 MiB | in-flight requests and cached roots |
| Other processes, ETS tables and runtime | 30 MiB | fixed |
| Allocator space holding no live data | 30 MiB | heap peaks |
| C allocator, native libraries and thread stacks | 130 MiB | fixed |
| **Resident (`rss`)** | **255 MiB** (peaks 265) | |

The Rust libraries return their memory after every call: between requests they
hold under 3 MiB. Releases start the VM with `+MMmcs 0`, so freed memory
segments go back to the operating system instead of staying cached without being
reported, and they trim the C allocator every 10 seconds. Without both, `rss`
was 20 to 35% higher at the same load.

Flat manifests (`PULSE_MANIFEST_FORMAT=flat`, or roots not yet converted) cost
about 2 KiB of node memory per segment, summed over tenants and signals, because
their owners and every query decode the whole list: the same node used 400 MiB
at 100,000 flat segments and 540 MiB at 200,000.

### Sizing formula

```text
limit ≈ 1.25 × ( 260 MiB
               + in-flight ingest requests × request size  (at most 32 MiB each)
               + PULSE_INGEST_MAX_PENDING_BYTES             (with coalescing)
               + running queries and workers × query heap ceiling
               + PULSE_OBJECT_CACHE_MEMORY_MB                (default 64 MiB)
               + 2 KiB × segments in flat manifests )
```

Typical exporter batches use far less than the 32 MiB worst case: Alloy
requests here took under 0.1 MiB each. Queries can reach their heap ceiling, so
budget it for the queries you expect to run at once, plus the alerting and
reliability workers when they are enabled. Enforced retention runs one more
maintenance worker with a heap ceiling of about 500 MiB while it converts or
expires a manifest; budget it on maintenance instances.

## Memory pressure

Pulse treats memory in three classes, as other observability backends do:

- **Caches are evicted.** Manifest roots are cached up to
  `PULSE_MANIFEST_CACHE_MAX_BYTES` (128 MiB) and manifest pages up to 16 MiB,
  least recently used first. An evicted root is reloaded from object storage on
  its next use.
- **In-flight work is admitted or refused.** Ingest and query slots bound
  concurrent work; excess requests get a retryable `429`.
- **Runaway work is aborted.** Per-query sample, work and scan budgets and the
  query heap ceiling fail one query, never the node.

Acknowledged data is never evicted: it is durable in object storage before the
acknowledgment.

On top of that, each node samples its resident memory every second. At
`PULSE_MEMORY_PRESSURE_PERCENT` (85%) of its limit it enters memory pressure:
new interactive queries are refused with a retryable overload error (`429`, MCP
`query_overloaded`) and manifest roots unused for 30 seconds are evicted. Roots
in active use are not
evicted: their owners republish them on every write, so evicting them would
free nothing and make every reader reload. Ingest keeps its own slots, and
alerting and reliability workers keep running. Pressure ends once resident
memory has stayed 10 points below the threshold for 10 seconds, so query bursts
do not make it flap. The
limit is `PULSE_MEMORY_BUDGET_MB`, otherwise the container's cgroup limit,
re-read every 15 seconds so an in-place resize takes effect; slot counts are
still derived at startup. Watch `pulse_memory_pressure`,
`pulse_memory_pressure_transitions_total` and
`pulse_admission_rejections_total{layer="query",reason="memory"}`. Frequent
pressure means the node is undersized. On nodes with flat manifests (no paged
format, no retention) memory grows with history, so a node can stay in pressure
until it is resized or upgraded. Pressure sheds load, not memory already held:
it keeps queries from adding to it. Query slots and per-query budgets are the
primary bound; in soak tests of paged nodes they kept memory flat without
pressure ever triggering.

## Per-tenant limits

Without configuration, each signal's ingest slots are already shared fairly
between the tenants sending to an instance: a tenant above its equal share is
refused while another active tenant needs a slot (see
[ingest admission](configuration.md#ingest-admission)). That protects tenants
from each other under load but does not cap a tenant on an idle instance.
`PULSE_TENANT_LIMITS_JSON` (chart `tenantLimits`) adds configured bounds on
top, from a `default` entry and per-tenant overrides:

```json
{
  "default": {"ingest_max_concurrent": 8, "query_max_concurrent": 2},
  "tenants": {"acme": {"ingest_bytes_per_second": 10485760, "query_max_concurrent": 4}}
}
```

| Field | Meaning |
| --- | --- |
| `ingest_max_concurrent` | Ingest requests one tenant may process at once on an instance, across signals. A request stops counting once it hands its slot off while waiting for publication. |
| `ingest_bytes_per_second` | Token-bucket rate over request wire bytes (`Content-Length`; requests without one count as 1 MiB). |
| `ingest_burst_bytes` | Bucket size; defaults to twice the rate and at least 4 MiB, so one maximum-size request always fits. |
| `query_max_concurrent` | Interactive queries one tenant may run at once on an instance (default 2). |

A missing field means no tenant-specific ingest bound. Requests over a tenant's
bound get the same retryable `429` (gRPC `RESOURCE_EXHAUSTED`) as node overload,
with reason `tenant_concurrency` or `tenant_rate` in
`pulse_admission_rejections_total`. Limits are charged only after the caller's
credentials verify for the tenant they name, so a forged `X-Scope-OrgID` cannot
spend another tenant's allowance. Sentry ingestion uses only the fair share.

Limits are per instance: behind a balancer spreading a tenant over N instances,
the tenant can use up to N times its rate. Divide the intended cluster-wide rate
by the number of ingest instances when you set it.

## Autoscale on saturation, not memory

With fixed slots, memory stays roughly flat under load, so it is a poor
autoscaling signal. Use slot saturation and CPU instead. These are exported on
the private [`/metrics`](self-monitoring.md) endpoint of every instance:

| Signal | Expression |
| --- | --- |
| Ingest saturation | `pulse_ingest_inflight_requests / pulse_ingest_max_concurrent_requests` |
| Ingest refusals | `sum by (signal) (rate(pulse_ingest_admission_total{outcome="rejected"}[5m]))` |
| Query saturation | `pulse_query_inflight / pulse_query_max_concurrent` |
| Query refusals | `rate(pulse_admission_rejections_total{layer="query",reason="node"}[5m])` |
| Memory pressure | `max_over_time(pulse_memory_pressure[5m])` |

Ingest refusals include `tenant_limited` ones (fair-share refusals while free
slots were kept for other tenants). Query refusals with reason `tenant` and
`pulse_admission_rejections_total{layer="ingest"}` (`tenant_concurrency`,
`tenant_rate`) come from per-tenant limits, not node capacity; adding instances
does not help with those.

## Separate pools

By default every instance runs every role. `PULSE_ROLES` (chart `pools.enabled`)
splits them:

- **ingest** runs the receivers (OTLP over HTTP and gRPC, Loki push, remote
  write, Sentry);
- **query** runs query, discovery, MCP and management APIs;
- **maintenance** runs compaction, retention, alert evaluation, error projection
  and reliability workers, and serves no traffic.

Separate pools scale independently, and a heavy query can no longer take memory
or CPU from ingest on the same instance. An instance answers requests for a role
it does not run with a retryable `503`, so a misrouted batch is retried rather
than lost. With `pools.enabled`, the chart creates one Service per traffic pool
and routes receiver paths (`/v1/*`, `/otlp/v1/*`, `/loki/api/v1/push`,
`/api/v1/write`, `/api/v1/push`, `/api/prom/push`) to the ingest pool and all
other paths to the query pool. Point in-cluster senders at the
`<release>-ingest` Service and readers at `<release>-query`.

## Clustering

Instances work without knowing about each other. With `clustering.enabled` the
chart joins them into one Erlang cluster through a headless Service, and
rendezvous hashing assigns each tenant's background compaction, retention and
alert evaluation to one maintenance instance instead of every instance
attempting it. This only reduces duplicate work: conditional object writes keep
results correct when ownership overlaps during membership changes. Keep the pods
on a trusted network; Erlang distribution authenticates with a shared cookie
only. Requests are never forwarded between instances, so data never crosses the
cluster connection.

## Limits that do not scale with instances

- Per-instance limits are not cluster limits. Each instance enforces its own
  slots.
- Every instance that writes a tenant's signal competes on the same manifest
  with conditional writes. More instances mean more conflicts and retries for
  busy tenants, and more object-store requests overall.
