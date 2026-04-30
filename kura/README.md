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
- 📦 Kura actively supports Bazel and Buck2 REAPI, Xcode Cache, Gradle, and [Tuist Module Cache](https://tuist.dev/en/docs/guides/features/cache/module-cache)
- 🧪 Compatibility endpoints for Nx and React Native Metro are available, but they are not a primary focus today
- 🧰 The gRPC API exposes the Bazel Remote Execution cache services used by Bazel and Buck2
- 📊 The local stack includes Grafana, Prometheus, Loki, Promtail, and Tempo traces

## Supported cache protocols

Actively supported:

- `Bazel` and `Buck2`: Bazel Remote Execution API v2 over gRPC on `KURA_GRPC_PORT`
- `Xcode Cache`: HTTP CAS artifacts on `POST/GET /api/cache/cas/{id}` and action-cache style entries on `PUT/GET /api/cache/keyvalue`
- `Gradle`: `PUT/GET /api/cache/gradle/{cache_key}`
- [`Module Cache`](https://tuist.dev/en/docs/guides/features/cache/module-cache): multipart uploads on `POST /api/cache/module/start`, `POST /api/cache/module/part`, `POST /api/cache/module/complete`, and `HEAD/GET /api/cache/module/{id}`

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

Kura exposes multiple cache protocols behind one service. The actively supported surfaces are:

- 🛠️ `Bazel` and `Buck2`: REAPI over gRPC on `KURA_GRPC_PORT`
- 🍎 `Xcode Cache`: `POST/GET /api/cache/cas/{id}?tenant_id=...&namespace_id=...`
- 🗂️ `KeyValue / action-cache entries`: `PUT /api/cache/keyvalue?tenant_id=...&namespace_id=...`
- 🐘 `Gradle`: `PUT/GET /api/cache/gradle/{cache_key}?tenant_id=...&namespace_id=...`
- 📦 [`Module Cache`](https://tuist.dev/en/docs/guides/features/cache/module-cache): `POST /api/cache/module/start?...`, `POST /api/cache/module/part?...`, `POST /api/cache/module/complete?...`, `HEAD/GET /api/cache/module/{id}?...`

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

Set `KURA_SENTRY_DSN` to also forward panics and `tracing::error!` events to Sentry. In Helm deployments, inject it via `extraEnv` or `extraEnvFrom`.

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

### Disabling OTLP tracing

OTLP tracing is optional. Leaving `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` unset (or empty) makes Kura skip exporter initialization and run without distributed traces — useful in environments without a collector (local kind, isolated edge nodes). Helm operators control it by setting `config.telemetry.otlpTracesEndpoint: ""` in a values overlay; the chart only renders the env when the value is non-empty, so an empty overlay disables tracing without crashlooping the pod.

## 📣 Runtime Analytics

Analytics webhooks are a separate optional subsystem that mirrors the older Tuist cache contract for Xcode and Gradle traffic.

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
  --set image.repository=ghcr.io/tuist/kura \
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
  --set image.repository=ghcr.io/tuist/kura \
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

The runtime keeps decision caching, metrics, timeouts, and cryptographic primitives in Rust, while the script supplies policy.
