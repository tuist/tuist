<p align="center">
  <img src=".github/assets/kura-logo.png" alt="Kura logo" width="420" />
</p>

# Kura

`Kura` is a Rust server for building low-latency cache meshes for tenants, handling distributed cache traffic for binary artifacts and metadata.

> [!NOTE]
> `Kura` comes from the Japanese word `蔵` (`kura`), which refers to a storehouse or warehouse. The name fits the system's role: keeping build artifacts and cache metadata stored durably and close at hand so they can be served with low latency.

## Summary ✨

- ⚡ Hot reads come from local disk
- 🪨 Local metadata, multipart state, and the replication outbox live in RocksDB
- 🔁 Blobs and cache metadata replicate to peer nodes with eventual consistency
- 🔎 Nodes can discover peers through DNS and bootstrap themselves from already-running nodes
- 📦 Kura actively supports Bazel and Buck2 REAPI, Xcode Cache, Gradle, and module-cache protocols
- 🧪 Compatibility endpoints for Nx and React Native Metro are available, but they are not a primary focus today
- 🧰 The gRPC API exposes the Bazel Remote Execution cache services used by Bazel and Buck2
- 📊 The local stack includes Grafana, Prometheus, Loki, Promtail, and Tempo traces

## Supported cache protocols

Actively supported:

- `Bazel` and `Buck2`: Bazel Remote Execution API v2 over gRPC on `KURA_GRPC_PORT`
- `Xcode Cache`: HTTP CAS artifacts on `POST/GET /api/cache/cas/{id}` and action-cache style entries on `PUT/GET /api/cache/keyvalue`
- `Gradle`: `PUT/GET /api/cache/gradle/{cache_key}`
- `Module Cache`: multipart uploads on `POST /api/cache/module/start`, `POST /api/cache/module/part`, `POST /api/cache/module/complete`, and `HEAD/GET /api/cache/module/{id}`

Compatibility surfaces:

- `Nx`: self-hosted remote cache API on `GET/PUT /v1/cache/{hash}`
- `React Native Metro`: `HttpStore` / `HttpGetStore` on `GET/PUT /api/metro/cache/{cache_key}`

## Local stack 🧪

Run:

```bash
docker compose up --build -d
```

Useful endpoints:

- `http://localhost:4101/up`
- `http://localhost:4101/ready`
- `http://localhost:4101/status/rollout`
- `http://localhost:4102/up`
- `http://localhost:4102/ready`
- `http://localhost:4102/status/rollout`
- `http://localhost:4103/up`
- `http://localhost:4103/ready`
- `http://localhost:4103/status/rollout`
- `grpc://localhost:5101` for Bazel/Buck2 REAPI against `kura-us`
- `grpc://localhost:5102` for Bazel/Buck2 REAPI against `kura-eu`
- `grpc://localhost:5103` for Bazel/Buck2 REAPI against `kura-ap`
- `http://localhost:3000` for Grafana with `admin` / `admin`
- `http://localhost:9090` for Prometheus
- `http://localhost:3100` for Loki
- `http://localhost:3200` for Tempo

## Toolchain 🛠️

Install Rust from `mise.toml`:

```bash
mise trust mise.toml
mise install
```

Run tests:

```bash
mise x rust@1.94.1 -- cargo test
mise x shellspec@0.28.1 -- shellspec
```

Runtime configuration is summarized in the table under [Runtime Model And Limits](#-runtime-model-and-limits). Kura now derives sensible defaults for the main FD, memory, and metadata-store budgets at startup when you do not set them explicitly.

## 🗺️ Project Areas

Kura is easier to read by subsystem than by tutorial step. The sections below group the project by the main areas you operate or extend.

- 🔌 [Protocol surfaces](#-protocol-surfaces)
- 🗄️ [Storage and replication](#-storage-and-replication)
- ⚙️ [Runtime model and limits](#-runtime-model-and-limits)
- 📊 [Observability](#-observability)
- 📣 [Runtime analytics](#-runtime-analytics)
- ☸️ [Deployment options](#-deployment-options)
- 🧩 [Extensions and policy](#-extensions-and-policy)

## 🔌 Protocol Surfaces

Kura exposes multiple cache protocols behind one service. Public HTTPS supports HTTP/2 so clients can multiplex concurrent artifact downloads on long-lived connections. The actively supported surfaces are:

- 🛠️ `Bazel` and `Buck2`: REAPI over gRPC on `KURA_GRPC_PORT`
- 🍎 `Xcode Cache`: `POST/GET /api/cache/cas/{id}?tenant_id=...&namespace_id=...`
- 🗂️ `KeyValue / action-cache entries`: `PUT /api/cache/keyvalue?tenant_id=...&namespace_id=...`
- 🐘 `Gradle`: `PUT/GET /api/cache/gradle/{cache_key}?tenant_id=...&namespace_id=...`
- 📦 `Module Cache`: `POST /api/cache/module/start?...`, `POST /api/cache/module/part?...`, `POST /api/cache/module/complete?...`, `HEAD/GET /api/cache/module/{id}?...`

For those HTTP cache routes, `tenant_id` is always required and `namespace_id` is optional. When `namespace_id` is present, the request is namespace-scoped. When it is omitted, the request is tenant-scoped and Kura stores it under an internal empty namespace key. REAPI requests still carry their namespace explicitly.

Kura also exposes compatibility endpoints that are not a primary focus today:

- 🧱 `Nx`: `PUT/GET /v1/cache/{hash}`
- 📱 `Metro`: `PUT/GET /api/metro/cache/{cache_key}`

The local compose stack is still the quickest way to exercise all of those surfaces together:

```bash
docker compose up --build -d
```

Example Xcode artifact round trip:

```bash
curl -X POST \
  "http://localhost:4101/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios" \
  -H "content-type: application/octet-stream" \
  --data-binary "xcode-binary"

curl \
  "http://localhost:4102/api/cache/cas/artifact-1?tenant_id=acme&namespace_id=ios"
```

Example keyvalue entry round trip:

```bash
curl -X PUT \
  "http://localhost:4101/api/cache/keyvalue?tenant_id=acme&namespace_id=ios" \
  -H "content-type: application/json" \
  -d '{"cas_id":"cas-1","entries":[{"value":"hello"},{"value":"world"}]}'

curl \
  "http://localhost:4103/api/cache/keyvalue/cas-1?tenant_id=acme&namespace_id=ios"
```

Example tenant-scoped Xcode artifact round trip without a namespace:

```bash
curl -X POST \
  "http://localhost:4101/api/cache/cas/account-artifact?tenant_id=acme" \
  -H "content-type: application/octet-stream" \
  --data-binary "account-binary"

curl \
  "http://localhost:4102/api/cache/cas/account-artifact?tenant_id=acme"
```

## 🗄️ Storage And Replication

Kura splits storage into two planes:

- 🪨 RocksDB stores metadata, keyvalue payloads, multipart state, tombstones, segment lifecycle state, and the replication outbox.
- 📦 Segment files store large immutable binary artifacts for the hot path.

Replication is leaderless and eventually consistent:

- 🔁 local writes become durable together with their outbox work
- 🌍 peers bootstrap by pulling manifests, tombstones, and artifact bodies
- 🔎 DNS discovery can expand the peer set automatically
- 🧠 the outbox is processed incrementally so queue depth does not blow up heap usage during backlog

Peer-to-peer traffic always uses the dedicated internal plane:

- `KURA_INTERNAL_PORT`

Peer-to-peer mTLS is optional on that plane:

- `KURA_INTERNAL_TLS_CA_CERT_PATH`
- `KURA_INTERNAL_TLS_CERT_PATH`
- `KURA_INTERNAL_TLS_KEY_PATH`

When peer mTLS is disabled:

- `KURA_NODE_URL` and every value in `KURA_PEERS` must use `http://...:<KURA_INTERNAL_PORT>`
- `/_internal/*` is only served on the internal HTTP listener
- 🌍 the public API still stays on `KURA_PORT`

When peer mTLS is enabled:

- 🔒 `KURA_NODE_URL` and every value in `KURA_PEERS` must use `https://...:<KURA_INTERNAL_PORT>`
- 🧱 `/_internal/*` is only served on the internal mTLS listener
- 🌍 the public API still stays on `KURA_PORT`
- 🪪 the certificate configured through `KURA_INTERNAL_TLS_CERT_PATH` should be valid for both server and client auth
- 🏷️ the certificate SANs must cover the hostname used in `KURA_NODE_URL`

## ⚙️ Runtime Model And Limits

Kura is designed around explicit resource budgets instead of relying on ambient process limits.

When `Optional` is `Yes`, the `Default` column shows what Kura uses today. `auto` means Kura derives the value at startup from detected file-descriptor limits, memory limits, or CPU count.

| Name | Description | Optional | Default |
| --- | --- | --- | --- |
| `KURA_PORT` | Public HTTP port. | No | `—` |
| `KURA_GRPC_PORT` | gRPC port for REAPI. | No | `—` |
| `KURA_INTERNAL_PORT` | Internal HTTP or mTLS port used for peer replication and discovery. | No | `—` |
| `KURA_GRPC_TLS_CERT_PATH` | PEM cert path used to terminate TLS on the public gRPC listener. | Yes | disabled |
| `KURA_GRPC_TLS_KEY_PATH` | PEM private-key path paired with `KURA_GRPC_TLS_CERT_PATH`. | Yes | disabled |
| `KURA_TENANT_ID` | Default tenant identifier for the node. | No | `—` |
| `KURA_REGION` | Region label advertised in metrics and replication state. | No | `—` |
| `KURA_TMP_DIR` | Temporary directory for staged request bodies and multipart assembly. | No | `—` |
| `KURA_DATA_DIR` | Persistent directory for metadata state and segment files. | No | `—` |
| `KURA_NODE_URL` | Canonical internal URL other peers use to reach this node. | No | `—` |
| `KURA_PEERS` | Seed peer list used before discovery converges. | Yes | `KURA_NODE_URL` |
| `KURA_DISCOVERY_DNS_NAME` | DNS name to probe for automatic peer discovery. | Yes | disabled |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | App-managed file-descriptor budget for request and background I/O. | Yes | auto |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | How long a request waits before FD backpressure fails the checkout. | Yes | `5000` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | Maximum grace window Kura gives in-flight HTTP and gRPC work to finish during shutdown before forcing exit progression. | Yes | `240000` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | Maximum number of pinned segment read handles; must stay below the FD pool size. | Yes | auto |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Soft watermark where Kura starts shedding optional memory use. | Yes | auto |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Hard watermark where Kura pauses replication work and trims hot caches aggressively. | Yes | auto |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | Maximum size of the in-memory manifest hot cache. | Yes | auto |
| `KURA_MAX_KEYVALUE_BYTES` | Maximum per-request keyvalue payload size on public and replication APIs. | Yes | `1048576` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | Descriptor budget reserved for the metadata store itself. | Yes | auto |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | Background flush and compaction concurrency for the metadata store. | Yes | auto |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | Capacity of the metadata-store read cache. | Yes | auto |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | Total memory budget reserved for metadata write buffering. | Yes | auto |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | Size of each metadata write buffer before flush. | Yes | auto |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | Maximum number of metadata write buffers kept in memory. | Yes | auto |
| `KURA_OUTBOX_MAX_DEPTH` | Maximum number of replication outbox messages allowed before public writes return 503 with Retry-After. | Yes | `100000` |
| `KURA_CONTROL_PLANE_URL` | Base URL for the control plane Kura reports usage to. When set with the client credentials below, Kura pushes usage rollups to `/_internal/kura/usage`. | Yes | disabled |
| `KURA_CONTROL_PLANE_CLIENT_ID` | OAuth client id used for Kura control-plane calls. | Yes | disabled |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | OAuth client secret used for Kura control-plane calls. | Yes | disabled |
| `KURA_USAGE_WINDOW_SECS` | Usage rollup window size. Kura aggregates request traffic in memory by bounded dimensions before writing closed windows to the durable usage outbox. | Yes | `60` |
| `KURA_USAGE_FLUSH_INTERVAL_MS` | How often closed usage windows are flushed from memory to RocksDB. | Yes | `60000` |
| `KURA_USAGE_DELIVERY_INTERVAL_MS` | How often the usage outbox attempts delivery to the control plane. Delivery pauses under critical memory pressure. | Yes | `5000` |
| `KURA_USAGE_BATCH_SIZE` | Maximum number of usage rollups sent in one control-plane request. | Yes | `1000` |
| `KURA_USAGE_MAX_BUCKETS` | Maximum number of in-memory usage aggregation buckets. New buckets are rejected when this cap is reached. | Yes | `10000` |
| `KURA_USAGE_OUTBOX_MAX_DEPTH` | Maximum number of durable usage rollups retained in RocksDB before closed windows stop flushing. | Yes | `100000` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | How long an in-progress multipart upload may sit before the janitor expires it. | Yes | `86400000` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | How often the multipart janitor scans for stale uploads. | Yes | `600000` |
| `KURA_BOOTSTRAP_TIMEOUT_MS` | Maximum time a single bootstrap-from-peer task may run before it is cancelled. | Yes | `1800000` |
| `KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS` | Upper bound on concurrent bootstrap-from-peer tasks. Holds a semaphore so a discovery burst can't fan out unbounded. | Yes | `8` |
| `KURA_EXTENSION_CACHE_MAX_ENTRIES` | Maximum entries kept in each of the extension authenticate/authorize caches. New entries are dropped (with metric `extension_cache{result="rejected"}`) once the cap is reached and no expired entries remain. | Yes | `100000` |
| `KURA_TOKIO_WORKER_THREADS` | Number of tokio worker threads. Pin this to the cgroup CPU quota in containers; defaults to detected parallelism clamped to `[2, 16]`. | Yes | auto |

Kura also enforces a few hard-coded budgets that are not configurable:

- Replication ingest bodies on `/_internal/replicate/artifact` are capped at four times `MAX_SEGMENT_BYTES` (2 GiB) so a misbehaving peer cannot fill the data PVC. Bootstrap-from-peer fetches enforce the same ceiling for segment-backed artifacts and a 4 MiB ceiling for inline artifacts; bootstrap manifest and tombstone pages are capped at 32 MiB each.
- Public writes are rejected with `503 Service Unavailable` and a short `Retry-After` header when memory pressure reaches `Critical`, when the outbox is at `KURA_OUTBOX_MAX_DEPTH`, when the FD pool is exhausted, or when the data PVC has insufficient free space for a new segment.
- RocksDB column families are configured with explicit level-0 slowdown/stop triggers and pending compaction limits so backlog turns into write-side backpressure instead of unbounded write-buffer growth.
- Inline keyvalue payloads are buffered in memory before being written. Total RAM committed to inline payloads is bounded by `KURA_FILE_DESCRIPTOR_POOL_SIZE * KURA_MAX_KEYVALUE_BYTES`; both knobs are tuned together when sizing per-pod memory.
- On startup, the soft `RLIMIT_NOFILE` is raised to the hard limit so the FD pool, RocksDB file descriptors, and socket budget all share the maximum the container runtime allows.

Auto-derived defaults currently follow these rules:

- `file_descriptor_limit` comes from `RLIMIT_NOFILE` when available, otherwise Kura falls back to a conservative host default.
- `memory_limit_bytes` comes from the cgroup memory limit when available, otherwise Kura falls back to physical host memory.
- `cpu_count` comes from detected parallelism via the runtime.
- `KURA_FILE_DESCRIPTOR_POOL_SIZE` is `usable_fds / 8`, clamped to `[64, 256]`, where `usable_fds` is the detected FD limit minus reserved headroom.
- `KURA_SEGMENT_HANDLE_CACHE_SIZE` is `KURA_FILE_DESCRIPTOR_POOL_SIZE / 4`, clamped to `[16, 64]`, and then capped below the FD pool so transient work keeps headroom.
- `KURA_MEMORY_SOFT_LIMIT_BYTES` is `70%` of detected memory, rounded down to MiB boundaries, with a minimum of `128 MiB`.
- `KURA_MEMORY_HARD_LIMIT_BYTES` is `85%` of detected memory, rounded down to MiB boundaries, and always at least `64 MiB` above the soft limit.
- `KURA_MANIFEST_CACHE_MAX_BYTES` is `KURA_MEMORY_SOFT_LIMIT_BYTES / 16`, rounded down to MiB boundaries and clamped to `[8 MiB, 64 MiB]`.
- `KURA_METADATA_STORE_MAX_OPEN_FILES` is `usable_fds / 2`, clamped to `[128, 1024]`.
- `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` is `cpu_count`, clamped to `[1, 8]`.
- `KURA_METADATA_STORE_READ_CACHE_BYTES` is `memory_limit_bytes / 32`, rounded down to MiB boundaries and clamped to `[16 MiB, 128 MiB]`.
- `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` follows the same `memory_limit_bytes / 32` rule as the metadata-store read cache.
- `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` is `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES / 4`, rounded down to MiB boundaries and clamped to `[4 MiB, 32 MiB]`.
- `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` is `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES / KURA_METADATA_STORE_WRITE_BUFFER_BYTES`, clamped to `[2, 8]`.
- `KURA_MAX_KEYVALUE_BYTES` defaults to `1048576`, `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` defaults to `5000`, and `KURA_DRAIN_COMPLETION_TIMEOUT_MS` defaults to `240000`.

A minimal direct-binary deployment still looks like:

```bash
KURA_PORT=4000 \
KURA_GRPC_PORT=50051 \
KURA_INTERNAL_PORT=7443 \
KURA_TENANT_ID=default \
KURA_REGION=eu-central \
KURA_TMP_DIR=/tmp/kura \
KURA_DATA_DIR=/var/cache/kura \
KURA_NODE_URL=http://cache-1.internal:7443 \
KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces \
KURA_OTEL_SERVICE_NAME=kura-eu-central \
KURA_OTEL_DEPLOYMENT_ENVIRONMENT=production \
./target/release/kura
```

Set `KURA_SENTRY_DSN` to also forward panics and `tracing::error!` events to Sentry. Kura uses `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` as the Sentry environment, so set it to values such as `production`, `staging`, or `canary` when separating events by deployment. In the standalone Helm chart, inject the DSN via `extraEnv` or `extraEnvFrom`. In controller-managed Tuist deployments, set `kuraController.telemetry.deploymentEnvironment` and sync the DSN into `kura-shared-secrets` with `kuraController.sentry.externalSecret`.
`KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` accepts either an OTLP HTTP signal path such as `http://otel-collector:4318/v1/traces` or an OTLP gRPC root endpoint such as `http://otel-collector:4317`.

## 📊 Observability

Kura ships with a fairly complete local observability story:

- 📈 Prometheus metrics
- 📉 Grafana dashboards
- 🪵 Loki and Promtail logs
- 🧭 Tempo traces
- 🚨 Optional Sentry error reporting for panics and error-level tracing events

Prometheus exposes live metadata-store memory gauges:

- `kura_rocksdb_block_cache_usage_bytes`
- `kura_rocksdb_block_cache_pinned_usage_bytes`
- `kura_rocksdb_block_cache_capacity_bytes`
- `kura_rocksdb_write_buffer_usage_bytes`
- `kura_rocksdb_write_buffer_capacity_bytes`

Kura also exports:

- 📦 artifact read and write counters by `kind`, `client`, `artifact_class`, and `result`
- 🔁 replication latency and result metrics
- 💾 file descriptor pool pressure metrics
- 🧠 manifest cache occupancy and admission metrics

HTTP request counters keep bounded `route` and `status` labels by using Axum route templates such as `/api/cache/cas/{id}` and folding unmatched paths into `/_unmatched`. Request methods stay on OpenTelemetry spans instead of Prometheus labels, and client country counts live on the separate `kura_http_client_requests_total` counter. The `kura_http_request_duration_seconds` histogram intentionally has no `route` label and records only public non-probe requests. Keeping route-level latency in Prometheus would multiply every route by every histogram bucket, so route-specific latency belongs in sampled traces instead.

### GeoIP enrichment

The Kura container image vendors a [DB-IP IP-to-City Lite](https://db-ip.com/db/download/ip-to-city-lite) MMDB at `/opt/geoip/dbip-city-lite.mmdb`, so client geographic attribution is on by default. Location is resolved from the first hop in `X-Forwarded-For` (or `X-Real-IP`) at two granularities:

- country (ISO 3166-1): the `client_country` Prometheus label on `kura_http_client_requests_total` and the `geo.country.iso_code` OTel span attribute on `http.request` spans
- subdivision (ISO 3166-2, e.g. `US-CA`): the `geo.region.iso_code` OTel span attribute on `http.request` spans

Span and Resource attributes follow the OpenTelemetry [`geo.*` semantic conventions](https://opentelemetry.io/docs/specs/semconv/registry/attributes/geo/) so standard Grafana/Tempo tooling understands them out of the box. The Prometheus label stays `client_country` (short and Prometheus-idiomatic; semantic conventions cover spans/logs/resource, not metric label names).

Subdivision is intentionally **not** a Prometheus label. ISO 3166-2 has thousands of codes, and multiplying it across route × status would inflate active series. It lives on sampled traces only, which is enough to compute geographic distance per request. Country stays on a dedicated low-cardinality metric because it is bounded (~250 codes).

Lookups that miss (no header, private IP, or DB missing) fall back to `client_country="unknown"` and an unset `geo.region.iso_code`. If the vendored database is absent (custom image builds), Kura logs a startup warning and quietly runs without geographic attribution.

A background task refreshes the in-memory database from `https://download.db-ip.com/free/dbip-city-lite-YYYY-MM.mmdb.gz` every `KURA_GEOIP_REFRESH_INTERVAL_SECS` seconds (default `86400`). Set the interval to `0` to keep the vendored copy for the pod's lifetime. The swap takes the in-process `RwLock` write guard for the few microseconds needed to replace the reader; concurrent lookups never observe a partial state. The City dump is ~60 MiB compressed / ~125 MiB decompressed today; each download is bounded to 128 MiB compressed / 256 MiB decompressed with a 60-second timeout, so refresh memory stays predictably capped well within the pod's limit. Outcomes are tracked in `kura_geoip_refresh_total{result="ok|http_error|parse_error"}`.

DB-IP data is © DB-IP, released under CC BY 4.0.

### Node geographic attribution

Each pod resolves its own country and subdivision once at startup and stamps them on every exported OTel span as the `geo.country.iso_code` and `geo.region.iso_code` Resource attributes, alongside the existing `kura.region` (the cloud deployment region, e.g. `fr-par`) and `kura.tenant_id`. The same resolved country/subdivision also lands on the low-cardinality `kura_node_geo_info` Prometheus info metric so Grafana can map serving nodes without parsing traces. Combined with `geo.country.iso_code` / `geo.region.iso_code` on each request span, traces carry both endpoints of the request and Grafana can compute geographic distance directly off Tempo data.

Country resolution chain, tried in order:

1. `KURA_NODE_COUNTRY` env var (operator override; must be a 2-letter ISO code).
2. Public egress IP discovered via `https://api.ipify.org` (3-second timeout, best-effort), looked up against the vendored GeoIP database.
3. Explicit deployment-region mapping for the managed labels we use today (`eu-central` -> `DE`, `us-east` / `us-west` -> `US`), otherwise a real country prefix already present in `KURA_REGION` (`fr-par` -> `FR`, `nl-ams` -> `NL`).

Subdivision resolution: `KURA_NODE_SUBDIVISION` env var (operator override; ISO 3166-2 code such as `US-CA`), otherwise the same single egress-IP lookup. If the subdivision override is present, Kura derives the country directly from it and skips the extra probe unless subdivision itself is still missing. There is no deployment-region fallback for subdivision, so when neither the override nor the GeoIP lookup yields one, `geo.region.iso_code` is simply not stamped (the same is true of `geo.country.iso_code` when all three steps fail).

### Disabling OTLP tracing

OTLP tracing is optional. Leaving `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` unset (or empty) makes Kura skip exporter initialization and run without distributed traces — useful in environments without a collector (local kind, isolated edge nodes). When it is set, Kura auto-detects OTLP HTTP vs gRPC from the endpoint shape: `/v1/traces` paths use HTTP, while root collector endpoints such as `http://collector:4317` use gRPC. Helm operators control it by setting `config.telemetry.otlpTracesEndpoint: ""` in a values overlay; the chart only renders the env when the value is non-empty, so an empty overlay disables tracing without crashlooping the pod.

## 📣 Runtime Analytics

Analytics webhooks are a separate optional subsystem for Tuist's current project-scoped cache analytics contract for Xcode and Gradle traffic.

Kura emits those webhook events only for namespace-scoped Xcode and Gradle HTTP requests, using the request's `tenant_id` and `namespace_id` as `account_handle` and `project_handle` in the payload. Tenant-scoped requests skip analytics until Tuist grows account-scoped binary analytics.

When enabled:

- 🍎 Xcode upload and download events are sent to `/webhooks/cache`
- 🐘 Gradle upload and download events are sent to `/webhooks/gradle-cache`
- ✍️ requests are signed with `x-cache-signature`
- 🧭 requests also include `x-cache-endpoint`
- 🪶 delivery stays in-memory and best-effort, so analytics never block the hot path
- 🧯 a per-pipeline circuit breaker opens after repeated delivery failures so Kura sheds analytics instead of backing up under a misbehaving upstream

Configure it with:

- `KURA_ANALYTICS_SERVER_URL`
- `KURA_ANALYTICS_SIGNING_KEY`
- optional `KURA_ANALYTICS_BATCH_SIZE` default `100`
- optional `KURA_ANALYTICS_BATCH_TIMEOUT_MS` default `5000`
- optional `KURA_ANALYTICS_QUEUE_CAPACITY` default `1000`
- optional `KURA_ANALYTICS_REQUEST_TIMEOUT_MS` default `5000`
- optional `KURA_ANALYTICS_CIRCUIT_BREAKER_FAILURE_THRESHOLD` default `5`
- optional `KURA_ANALYTICS_CIRCUIT_BREAKER_OPEN_MS` default `30000`

It also exposes analytics-specific runtime metrics for:

- 📣 queue depth and drops
- 📦 batch sizes and flush outcomes
- 🧯 circuit-breaker state and open events

## Usage Metering

When `KURA_CONTROL_PLANE_URL`, `KURA_CONTROL_PLANE_CLIENT_ID`, and `KURA_CONTROL_PLANE_CLIENT_SECRET` are set, Kura records first-party usage rollups for public cache traffic and pushes them to:

```text
POST {KURA_CONTROL_PLANE_URL}/_internal/kura/usage
```

The hot path increments bounded in-memory counters keyed by tenant, namespace, node, region, traffic plane, direction, operation, protocol, artifact kind, and fixed time window. Closed windows are persisted to a dedicated RocksDB usage outbox, then delivered in bounded batches with HTTP Basic client credentials. Delivery is at least once; the control plane deduplicates by deterministic `event_id`.

The usage pipeline follows Kura's resource discipline: bucket count, durable outbox depth, and delivery batch size are capped; delivery pauses under critical memory pressure; and a full usage outbox causes new closed windows to remain in memory until the in-memory bucket cap is reached, after which new buckets are rejected and counted through memory-action metrics.

## ☸️ Deployment Options

### Helm And Kubernetes

The repository includes a Helm chart at `ops/helm/kura` that deploys Kura as a `StatefulSet` with:

- 💾 one PVC per pod for metadata-state and segment storage
- 🔒 single-writer fencing through a process-held data-dir lock plus `ReadWriteOncePod` by default
- 🧭 a headless service for stable pod DNS and peer discovery
- 🌐 a regular service exposing both HTTP and gRPC
- 🚪 optional ingress for the HTTP API
- 🧩 optional inline extension script mounting through a `ConfigMap`
- 🔐 optional peer mTLS for `/_internal/*` traffic via a mounted Kubernetes `Secret`
- 🚦 `/ready` for public readiness and `/up` for liveness, with a `preStop` `SIGUSR1` drain hook that removes pods from traffic before `SIGTERM`
- ⏱️ a pod grace period derived from Kura's own drain timeout plus small lifecycle buffers so Kubernetes does not cut shutdown short

Lint and render the chart:

```bash
helm lint ops/helm/kura
helm template kura ops/helm/kura --namespace kura
```

Install it on a generic cluster:

```bash
helm upgrade --install kura ./ops/helm/kura \
  --namespace kura \
  --create-namespace \
  --set image.repository=<registry>/kura \
  --set image.tag=latest \
  --set config.region=fr-par \
  --set config.telemetry.otlpTracesEndpoint=http://otel-collector.monitoring.svc.cluster.local:4318/v1/traces
```

The chart defaults persistence to `ReadWriteOncePod` so one Kura process owns each PVC. If your CSI driver does not support it, override `persistence.accessModes[0]=ReadWriteOnce`; Kura will still fence the volume with its app-level writer lock.

The chart computes `terminationGracePeriodSeconds` from `config.shutdown.drainCompletionTimeoutMs`, `podLifecycle.preStopDelaySeconds`, and `podLifecycle.terminationGraceExtraSeconds`. That keeps the platform budget aligned with the application's shared shutdown deadline instead of relying on a separate hard-coded Kubernetes timeout.

For a local kind smoke test, the repo includes:

```bash
./test/e2e/kura_helm_kind.sh
```

For a gated in-place StatefulSet rollout, the repo also includes:

```bash
./ops/helm/kura/rollout.sh kura kura --set image.tag=<new-tag>
```

That script is the Kubernetes adapter. The rollout gate itself lives in `ops/rollout/gate.sh` and only assumes it can fetch Kura's rollout status endpoint once per node per poll. The Helm adapter stages the new revision behind a StatefulSet partition, rolls the highest ordinal first, and only advances after every node reports the same membership generation, all nodes are back in `serving`, the updated pod stays ready, ring membership is restored cluster-wide, outbox depth stays near baseline, no node is under critical memory pressure, and the cluster is not introducing new file-descriptor timeout activity.

If the Kura container listens on a non-default HTTP port, set `KURA_HTTP_PORT=<port>` when invoking the rollout helper so the adapter samples the correct loopback endpoint inside each pod.

For adjacent-version mixed rollout and rollback validation on the same persistent Docker volumes, use:

```bash
PREVIOUS_REF=origin/main ./test/e2e/kura_compatibility_rollout.sh
```

That harness proves `PREVIOUS_REF -> HEAD -> PREVIOUS_REF` across a mixed-version window, but it validates protocol and on-disk compatibility only. It does not try to model Kubernetes PVC reattachment behavior.

To enable peer mTLS in Kubernetes, set:

- `peerTls.enabled=true`
- `peerTls.internalPort=<port>`
- `peerTls.secretName=<secret-with-ca-cert-and-key-material>`

The referenced secret should contain the files configured by:

- `peerTls.caCertFileName`
- `peerTls.certFileName`
- `peerTls.keyFileName`

When enabled, the chart advertises peer URLs over `https` on the internal port and mounts the secret into `/etc/kura/peer-tls`.

### Scaleway Kapsule

For Scaleway, start from the bundled overrides in `ops/helm/kura/values-scaleway.yaml`:

```bash
helm upgrade --install kura ./ops/helm/kura \
  --namespace kura \
  --create-namespace \
  -f ./ops/helm/kura/values-scaleway.yaml \
  --set image.repository=<registry>/kura \
  --set image.tag=latest \
  --set config.region=fr-par \
  --set config.telemetry.otlpTracesEndpoint=http://otel-collector.monitoring.svc.cluster.local:4318/v1/traces
```

That values file does two important things:

- 🚪 uses a `LoadBalancer` service, which is the simplest way to expose Kura on Kapsule
- 💾 pins persistence to `scw-bssd`, which Scaleway documents as the default block storage class for Kapsule multi-AZ clusters

## 🧩 Extensions And Policy

Kura can load one operator-provided extension script at startup to customize authentication, authorization, and response headers without recompiling the binary.

Core env vars:

- `KURA_EXTENSION_ENABLED=true`
- `KURA_EXTENSION_SCRIPT_PATH=/etc/kura/extensions/hooks.lua`
- `KURA_EXTENSION_HOOK_TIMEOUT_MS=25`
- `KURA_EXTENSION_AUTH_CACHE_ALLOW_TTL_SECONDS=600`
- `KURA_EXTENSION_AUTH_CACHE_DENY_TTL_SECONDS=3`
- `KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE=true`
- `KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE=true`
- `KURA_EXTENSION_FAIL_OPEN_RESPONSE_HEADERS=true`

Generic host resources are also env-driven:

- ✍️ signers:
  - `KURA_EXTENSION_SIGNER_<ID>_ALGORITHM`
  - `KURA_EXTENSION_SIGNER_<ID>_SECRET`
- 🪪 JWT verifiers:
  - `KURA_EXTENSION_JWT_VERIFIER_<ID>_ALGORITHM`
  - `KURA_EXTENSION_JWT_VERIFIER_<ID>_SECRET`
  - `KURA_EXTENSION_JWT_VERIFIER_<ID>_ISSUER`
  - `KURA_EXTENSION_JWT_VERIFIER_<ID>_AUDIENCES`
- 🌐 HTTP clients:
  - `KURA_EXTENSION_HTTP_CLIENT_<ID>_BASE_URL`
  - `KURA_EXTENSION_HTTP_CLIENT_<ID>_CONNECT_TIMEOUT_MS`
  - `KURA_EXTENSION_HTTP_CLIENT_<ID>_REQUEST_TIMEOUT_MS`

The script may define these hooks:

- `authenticate(ctx)`
- `authorize(ctx, principal)`
- `response_headers(ctx, principal)`

The runtime exports these host helpers to the script:

- `kura.sign_hmac_base64(id, payload)`
- `kura.jwt_verify(id, token)`
- `kura.http_json(id, request)`
- `kura.env(key)`

For tenant-aware deployments, `ctx` carries the request target
(`tenant_id`, `namespace_id`) and the node's configured tenant as
`server_tenant_id` (derived from `KURA_TENANT_ID`). Namespace-scoped
requests set `namespace_id`; tenant-scoped requests leave it unset.
Concrete auth and policy decisions are hook-specific and should be
documented with the hook implementation rather than in the generic
runtime contract.

The runtime keeps decision caching, metrics, timeouts, and cryptographic primitives in Rust, while the script supplies policy.
