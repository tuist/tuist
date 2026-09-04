<p align="center">
  <img src=".github/assets/kura-logo.png" alt="Kura logo" width="420" />
</p>

# Kura

`Kura` is a Rust server for building low-latency cache meshes for tenants, handling distributed cache traffic for binary artifacts and metadata.

> [!NOTE]
> `Kura` comes from the Japanese word `蔵` (`kura`), which refers to a storehouse or warehouse. The name fits the system's role: keeping build artifacts and cache metadata stored durably and close at hand so they can be served with low latency.

## License and Contributing

Kura is licensed under the GNU Affero General Public License, version 3 only. See [LICENSE.md](./LICENSE.md) for the full license text.

Contributions to Kura require signing the Kura Contributor License Agreement (CLA). Please see [CLA.md](./CLA.md) before submitting pull requests that modify Kura components.

## Summary ✨

- ⚡ Hot reads come from local disk
- 🪨 Local metadata, multipart state, and the replication outbox live in RocksDB
- 🔁 Blobs and cache metadata replicate to peer nodes with eventual consistency
- 🔎 Nodes can discover peers through DNS and catch up from already-running nodes
- 📦 Kura actively supports Bazel and Buck2 REAPI, Xcode Cache, Gradle, and module-cache protocols
- 🧪 Compatibility endpoints for Nx and React Native Metro are available, but they are not a primary focus today
- 🧰 The gRPC API exposes Bazel's [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache services
- 🧪 After committing a Bazel action-cache result, Kura can best-effort deliver its conventional `test.xml` and `test.log` outputs to Tuist without delaying cache traffic
- 🧰 The gRPC API exposes Bazel's [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache services and [Build Event Service](https://bazel.build/remote/bep) receiver
- 📊 The local stack includes Grafana, Prometheus, Loki, Promtail, and Tempo traces

## Supported cache protocols

Actively supported:

- `Bazel` and `Buck2`: Bazel [Remote Execution API](https://github.com/bazelbuild/remote-apis) v2 cache services over gRPC on `KURA_PORT`; Bazel also reports completed commands through the [Build Event Service](https://bazel.build/remote/bep) on that port
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
- `grpc://localhost:4101` for Bazel/Buck2 Remote Execution API cache traffic and Bazel Build Event Service traffic against `kura-us`
- `grpc://localhost:4102` for Bazel/Buck2 Remote Execution API cache traffic and Bazel Build Event Service traffic against `kura-eu`
- `grpc://localhost:4103` for Bazel/Buck2 Remote Execution API cache traffic and Bazel Build Event Service traffic against `kura-ap`
- `http://localhost:3000` for Grafana with `admin` / `admin`
- `http://localhost:9090` for Prometheus
- `http://localhost:3100` for Loki
- `http://localhost:3200` for Tempo

## Toolchain 🛠️

Install the toolchain (Rust + Bazel) from `mise.toml`:

```bash
mise trust mise.toml
mise install
```

Build and test with Bazel (the path CI gates on):

```bash
mise run compile         # build all targets for the host
mise run test-unit       # bazel test //...
```

rules_rs resolves the crate graph from `Cargo.toml`/`Cargo.lock` on each build, so changing Rust
deps just updates `Cargo.lock` as usual.

If you have access to the `tuist/kura` project on Tuist, run `tuist bazel setup` (and re-run it after
changing location) to use the closest Kura remote cache; otherwise Bazel builds fine against the
local cache.

Cargo works as a fallback when Bazel is unavailable, and the end-to-end suite runs under shellspec:

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
- 🔐 [Cache authorization](#-cache-authorization)

## 🔌 Protocol Surfaces

Kura exposes multiple cache protocols behind one service. Public HTTPS supports HTTP/2 so clients can multiplex concurrent artifact downloads on long-lived connections. The actively supported surfaces are:

- 🛠️ `Bazel` and `Buck2`: [Remote Execution API](https://github.com/bazelbuild/remote-apis) cache services over gRPC on `KURA_PORT`; Bazel's [Build Event Service](https://bazel.build/remote/bep) is co-hosted on the same port
- 🍎 `Xcode Cache`: `POST/GET /api/cache/cas/{id}?tenant_id=...&namespace_id=...`
- 🗂️ `KeyValue / action-cache entries`: `PUT /api/cache/keyvalue?tenant_id=...&namespace_id=...`
- 🐘 `Gradle`: `PUT/GET /api/cache/gradle/{cache_key}?tenant_id=...&namespace_id=...`
- 📦 `Module Cache`: `POST /api/cache/module/start?...`, `POST /api/cache/module/part?...`, `POST /api/cache/module/complete?...`, `HEAD/GET /api/cache/module/{id}?...`

Artifact GETs on those HTTP routes are resumable. Kura advertises `Accept-Ranges: bytes` on every artifact response, accepts a single `bytes=` range on the request, and answers it with `206 Partial Content` and a `Content-Range` header. A client whose download is cut short should re-request with `Range: bytes=<bytes it already has>-` and append, rather than restarting from zero. Multi-range requests are served whole; a range starting past the end of the artifact is refused with `416 Range Not Satisfiable` and a `Content-Range: bytes */<size>` header.

For those HTTP cache routes, `tenant_id` is always required and `namespace_id` is optional. When `namespace_id` is present, the request is namespace-scoped. When it is omitted, the request is tenant-scoped and Kura stores it under an internal empty namespace key. REAPI requests carry their namespace explicitly through the gRPC `instance_name`/`resource_name`, and may declare the account with the `x-kura-tenant-id` metadata header (the gRPC analog of the `tenant_id` query param above).

Kura extends the REAPI ActionCache with a wildcard form of the standard `GetActionResult.inline_output_files` hint: a literal `"*"` entry asks Kura to inline the contents of **every** output file the response budget affords (the per-request REAPI materialization budget, 8–64MB depending on the node's memory limits). It exists for clients whose output-file paths are digests unknown before the response — the Xcode CAS plugin — collapsing the action lookup and the blob fetch into one round-trip. Semantics: wildcard-matched files inline best-effort (a file the budget cannot afford stays un-inlined and the client falls back to `BatchReadBlobs`); explicitly listed paths keep the standard hard `RESOURCE_EXHAUSTED` error on budget exhaustion; servers without the extension match no literal `"*"` path and inline nothing, so mixed client/server versions interoperate unchanged. Note the trade-off: inlining happens before the server can know which blobs the client already holds, so every inlined byte counts as metered download egress even when a warm client discards it.

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
- 📦 Segment files store large immutable binary artifacts for the hot path. The segment ring's capacity derives from the data-dir filesystem size (or `KURA_CAS_CAPACITY_BYTES`), and rotating in a new segment evicts the oldest one once the budget is reached.

Replication is leaderless and eventually consistent:

- 🔁 local writes become durable together with their outbox work
- 🌍 a joining peer catches up newest-first through the backfill walker, listing its own per-entry index against each peer's and fetching only the bodies it is missing
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
| `KURA_PORT` | Plaintext port for the co-hosted HTTP cache API + h2c REAPI gRPC service (one listener, dispatched by request path). | No | `—` |
| `KURA_HTTPS_PORT` | TLS port serving the same co-hosted HTTP + gRPC surface (ALPN-negotiated), active when `KURA_PUBLIC_TLS_*` is configured. | Yes | `4443` |
| `KURA_INTERNAL_PORT` | Internal HTTP or mTLS port used for peer replication and discovery. | No | `—` |
| `KURA_TENANT_ID` | Default tenant identifier for the node. | No | `—` |
| `KURA_REGION` | Region label advertised in metrics and replication state. | No | `—` |
| `KURA_TMP_DIR` | Temporary directory for staged request bodies and multipart assembly. | No | `—` |
| `KURA_TMP_DIR_MAX_BYTES` | Process-wide byte budget shared by every temporary writer before requests receive backpressure. Reservations remain held until the staged file is moved or unlinked. | Yes | `8589934592` |
| `KURA_DATA_DIR` | Persistent directory for metadata state and segment files. | No | `—` |
| `KURA_CAS_CAPACITY_BYTES` | Artifact-body budget for the CAS segment ring. Rounded down to whole 512 MiB segments and capped at 80% of the `KURA_DATA_DIR` filesystem so segment rotation can never run the disk full. | Yes | 50% of the `KURA_DATA_DIR` filesystem (legacy 5-segment ring when the filesystem size cannot be determined) |
| `KURA_NODE_URL` | Canonical internal URL other peers use to reach this node. | No | `—` |
| `KURA_PEER_GATEWAY_URL` | Optional regional gateway URL advertised to peers discovered through global discovery. Use this when remote regions must replicate through a stable region-level endpoint rather than pod-local DNS. | Yes | `KURA_NODE_URL` |
| `KURA_PEERS` | Static seed peer list. Immutable for the process lifetime, so it should carry only platform-stable peers (enrollment seeds it with the managed regions' public peer gateways); volatile self-hosted membership flows through the mesh heartbeat instead. | Yes | empty |
| `KURA_MESH_PEERS_SYNC` | When `true` on a non-enrolled (managed) node, fetches the account's dynamic peer list from `{KURA_CONTROL_PLANE_URL}/_internal/kura/mesh/peers` at boot and on cadence, using the control-plane client credentials. Serving is gated on the first successful fetch, so a pod booting blind never accepts writes without enqueuing replication for peers it cannot see. | Yes | `false` |
| `KURA_DISCOVERY_DNS_NAME` | DNS name to probe for automatic peer discovery. | Yes | disabled |
| `KURA_GLOBAL_DISCOVERY_DNS_NAME` | Optional DNS name for cross-region gateway discovery. Status checks through this path advertise `KURA_PEER_GATEWAY_URL` instead of pod-local `KURA_NODE_URL`. | Yes | disabled |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | App-managed file-descriptor budget for request and background I/O. | Yes | auto |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | How long a request waits before FD backpressure fails the checkout. | Yes | `5000` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | Maximum grace window Kura gives in-flight HTTP and gRPC work to finish during shutdown before forcing exit progression. | Yes | `240000` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | Maximum number of pinned segment read handles; must stay below the FD pool size. | Yes | auto |
| `KURA_ACCELERATED_FILE_SERVING_ENABLED` | Enables the same-port Linux file serving accelerator for eligible plaintext HTTP/1 public artifact downloads. Non-Linux builds, HTTPS, HTTP/2, non-GET requests, inline artifacts, unsupported routes, and denied requests use the normal Axum/Hyper path. | Yes | `true` |
| `KURA_ACCELERATED_FILE_SERVING_MODE` | Linux kernel transfer primitive used by the accelerator: `splice` or `sendfile`. | Yes | `splice` |
| `KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT` | Maximum number of concurrent accelerated transfers per node. Requests above the limit fall back to the normal Axum/Hyper path before any request bytes are consumed. | Yes | `32` |
| `KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES` | Maximum per-syscall transfer size used by accelerated `splice`/`sendfile` loops. | Yes | `1048576` |
| `KURA_ACTION_CACHE_EVICTION_CASCADE_ENABLED` | When true, evicting a CAS blob cascades to the action-cache entries that reference it (removed in the same atomic batch) so an entry never outlives its blobs. Additionally gated on the node's one-time reverse-map backfill completing; the serve-side presence gates stay on regardless as the backstop. | Yes | `true` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Soft watermark where Kura starts shedding optional memory use. | Yes | auto |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Hard watermark where Kura pauses replication work and trims hot caches aggressively. | Yes | auto |
| `KURA_SNAPSHOT_CACHE_MAX_BYTES` | Maximum estimated retained bytes across action-cache snapshot indexes and cached encoded full views. | Yes | auto |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | Maximum size of the in-memory manifest hot cache. | Yes | auto |
| `KURA_MAX_KEYVALUE_BYTES` | Maximum per-request keyvalue payload size on public and replication APIs. | Yes | `1048576` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | Descriptor budget reserved for the metadata store itself. | Yes | auto |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | Background flush and compaction concurrency for the metadata store. | Yes | auto |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | Capacity of the metadata-store read cache. | Yes | auto |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | Total memory budget reserved for metadata write buffering. | Yes | auto |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | Size of each metadata write buffer before flush. | Yes | auto |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | Maximum number of metadata write buffers kept in memory. | Yes | auto |
| `KURA_OUTBOX_MAX_DEPTH` | Maximum number of replication outbox messages reserved atomically by the store before cache writes receive retryable backpressure. | Yes | `100000` |
| `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND` | Aggregate per-node byte-per-second ceiling for peer artifact body transfers. Kura dynamically divides this ceiling by the larger of `public_inflight + 1` and recent public request latency pressure, so sync traffic backs off while public HTTP or gRPC cache work is active or slow; `0` disables throttling. | Yes | `536870912` |
| `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS` | Public HTTP/gRPC request latency target used to adapt peer artifact body bandwidth. If recent public latency exceeds the target, sync traffic backs off proportionally; `0` disables latency-based pressure. | Yes | `100` |
| `KURA_REPLICATION_UPLOAD_STALL_MS` | Maximum time an outbox artifact upload may produce no body chunk before the attempt is abandoned and retried. Re-armed when the body ends, so the wait for the receiver's response gets a whole window. This is the only deadline on the upload path — the upload client carries no read timeout, because the response side stays silent until the receiver has consumed the whole body. | Yes | `60000` |
| `KURA_CONTROL_PLANE_URL` | Base URL for the control plane Kura reports usage to. When set with the client credentials below, Kura pushes usage rollups to `/_internal/kura/usage`. The same batches carry storage telemetry for control-plane claim sizing: a capacity-eviction report per segment the ring sheds under size pressure (with deterministic per-segment event ids) and a ring-occupancy snapshot at most every 15 minutes, both buffered in memory only with bounded queues. Falls back to `KURA_AUTH_TUIST_URL` when those credentials are set, since usage and authorization address the same server. | Yes | disabled |
| `KURA_CONTROL_PLANE_CLIENT_ID` | OAuth client id used for Kura control-plane calls. | Yes | disabled |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | OAuth client secret used for Kura control-plane calls. | Yes | disabled |
| `KURA_ENROLL_ON_BOOT` | When `true`, the node enrolls with the control plane on boot: it generates a keypair locally, sends a CSR to `/_internal/kura/mesh/enroll` with the control-plane credentials, writes the issued certificate, account CA, and key to the `KURA_INTERNAL_TLS_*` paths, and derives `KURA_TENANT_ID` and `KURA_PEERS` from the response. A background task then re-enrolls before the leaf expires and hot-reloads the new certificate into both the inbound mTLS server and the outbound peer client, so short leaves do not require a restart. Enrolled nodes also send a mesh heartbeat to `{KURA_CONTROL_PLANE_URL}/_internal/kura/mesh/heartbeat` (every 60s; the cadence is control-plane advertised): the control plane withholds peers that stop heartbeating from the mesh, and the response carries the current peer list, so peer additions and removals propagate at heartbeat cadence instead of at certificate renewal. A withheld node is answered `mesh_member: false` and recovers automatically with a backoff-limited re-enrollment, which restores its membership and arms a backfill pass for every peer in view; the writes it missed while out of the mesh were never enqueued for it, so those passes reconcile back to the backfill window from the node's durable watermarks, without leaving serving. This mesh heartbeat is independent from the registration heartbeat (`KURA_REGISTRATION_URL`), which advertises the node's client-facing endpoint. Requires `KURA_CONTROL_PLANE_*`, `KURA_NODE_URL`, and the three `KURA_INTERNAL_TLS_*` paths. | Yes | `false` |
| `KURA_REGISTRATION_URL` | Absolute URL of a control-plane registration endpoint. When set together with `KURA_ADVERTISED_HTTP_URL`, the node periodically POSTs a heartbeat (its node id, advertised HTTP cache URL, readiness, version, traffic state, ring size, and writer-lock ownership) authenticated with `KURA_CONTROL_PLANE_CLIENT_ID`/`KURA_CONTROL_PLANE_CLIENT_SECRET`. The control plane leases the registration and stops advertising the endpoint to clients when heartbeats stop. The payload is control-plane agnostic and the URL is absolute, so Kura never derives a control-plane route. | Yes | disabled |
| `KURA_ADVERTISED_HTTP_URL` | Client-facing HTTP cache URL advertised in registration heartbeats (for example a regional load balancer in front of the node). Distinct from `KURA_NODE_URL`, which is the internal peer/replication URL and must not be advertised to clients. | Yes | `—` |
| `KURA_REGISTRATION_INTERVAL_MS` | How often the node sends a registration heartbeat. | Yes | `60000` |
| `KURA_USAGE_WINDOW_SECS` | Usage rollup window size. Kura aggregates request traffic in memory by bounded dimensions before writing closed windows to the durable usage outbox. | Yes | `60` |
| `KURA_USAGE_FLUSH_INTERVAL_MS` | How often closed usage windows are flushed from memory to RocksDB. | Yes | `60000` |
| `KURA_USAGE_DELIVERY_INTERVAL_MS` | How often the usage outbox attempts delivery to the control plane. Delivery pauses under critical memory pressure. | Yes | `5000` |
| `KURA_USAGE_BATCH_SIZE` | Maximum number of usage rollups sent in one control-plane request. | Yes | `1000` |
| `KURA_USAGE_MAX_BUCKETS` | Maximum number of in-memory usage aggregation buckets. New buckets are rejected when this cap is reached. | Yes | `10000` |
| `KURA_USAGE_OUTBOX_MAX_DEPTH` | Maximum number of durable usage rollups retained in RocksDB before closed windows stop flushing. | Yes | `100000` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | How long an in-progress multipart upload may sit before the janitor expires it. | Yes | `86400000` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | How often the multipart janitor scans for stale uploads. | Yes | `600000` |
| `KURA_MULTIPART_MAX_ACTIVE_UPLOADS` | Process-wide cap on active multipart uploads. The count is rebuilt from durable upload records after a restart. | Yes | `128` |
| `KURA_MULTIPART_MAX_STORED_BYTES` | Process-wide byte cap for durable, incomplete multipart parts. Defaults to the temporary-directory byte budget when unset. | Yes | `KURA_TMP_DIR_MAX_BYTES` |
| `KURA_BACKFILL_MARGIN_PERCENT` | Share of the age-ordered segment ring (counted from the newest) whose boundary segment's seal-time stat becomes the backfill horizon; the margin's share of the ring's time span is the window's structural slack. | Yes | `40` |
| `KURA_BACKFILL_READY_RING_PERCENT` | Segment-ring fullness percent at which a node still running its initial backfill cycle marks itself ready; readiness then latches for the process lifetime. | Yes | half of `KURA_BACKFILL_MARGIN_PERCENT` |
| `KURA_BACKFILL_BATCH_BYTES` | Byte threshold a backfill pass composes one bodies batch against, and the cutoff above which a listed entry is fetched through the per-artifact endpoint. Must not exceed the compiled 32 MiB response ceiling shared by both sides of the bodies protocol. | Yes | `33554432` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | Maximum entries kept in each of the authentication and authorization caches. New entries are dropped once the cap is reached and no expired entries remain. | Yes | `100000` |
| `KURA_REQUEST_LOG_SAMPLE_RATE` | Fraction of successful request completions emitted as structured logs, deterministically selected by request identifier. Slow and failed request warnings are independent of this setting. | Yes | `0` |
| `KURA_SLOW_REQUEST_THRESHOLD_MS` | Total request duration that emits a structured slow-request warning. Set to `0` to disable these warnings. | Yes | `30000` |
| `KURA_WARNING_LOG_INTERVAL_MS` | Minimum interval between repeated warnings of the same bounded class. Suppressed counts are attached to the next emitted event. Set to `0` to disable rate limiting. | Yes | `60000` |
| `KURA_TOKIO_WORKER_THREADS` | Number of tokio worker threads. Pin this to the cgroup CPU quota in containers; defaults to detected parallelism clamped to `[2, 16]`. | Yes | auto |

### Backfill operations

- Backfill is the only peer catch-up path; there is no walker selection to make. A node builds its per-entry index at boot and answers `GET /_internal/backfill/entries` with `503 index_building` until `backfill/meta/build_complete` is set — a requester treats that as a budget-exempt retry, so a mesh whose peers are still indexing converges late rather than failing.
- The rollout report shows the initial cycle per node as `pending` (passes still running or retrying with budget left), `complete` (every in-cycle peer resolved cleanly), or `degraded` (a peer exhausted its failure budget on real failures).
- Region-move promotion gates on instance readiness only; the initial-cycle mode is not consumed by the control plane. A move target can latch ready before its full transfer settles, so before initiating a move where completeness matters, check `backfill_initial_cycle: complete` on the target's rollout report first. To abort a move, destroy the move TARGET server (`Kura.destroy_server` via the server ops surface); the source keeps serving.
- Index-build progress: a node still building answers listing requests with `503 index_building`; rebuilds (rollback-window staleness, cumulative crash forgiveness) are logged with the reason.

#### Wire protocol

A pass talks to a peer over three internal endpoints. All three are peer-plane routes, so mTLS and the peer verifier apply.

| Endpoint | Purpose |
|---|---|
| `GET /_internal/backfill/entries` | Lists the peer's index newest-first as `{record_kind, record_id, version_ms, size}` rows (`size` is absent for namespace tombstones). The requester pages with `?after=<cursor>&limit=<rows>`, passing back the page's `next_after`, and stops at its own window bound. Answers `503 index_building` while the peer is still indexing. |
| `POST /_internal/backfill/bodies` | Takes the tuples the requester decided it is missing and answers one length-prefixed frame per requested tuple, in request order. A frame is `Present` (header, manifest meta, then the body), `Absent` (the row is gone), or `FetchIndividually` (the body does not fit the batch). Batches are composed against `KURA_BACKFILL_BATCH_BYTES` and are bounded by a 32 MiB response ceiling both sides compile in. |
| `GET /_internal/backfill/artifacts/{artifact_id}` | One entry, framed exactly like a bodies frame. Used for entries above the batch threshold and for `FetchIndividually` bounces. |

Both sides spool through the filesystem: the sender writes frames to a temp file before responding, moving each owned segment-read chunk directly into the spool writer, and the requester streams the response to its own temp file and applies from disk, so neither holds a batch in memory. A frame carries the version, kind and manifest meta of the manifest its bytes were opened from, never the requested tuple's, so a mid-flight overwrite cannot land under a stale stamp.

Kura also enforces a few hard-coded budgets that are not configurable:

- Replication ingest bodies on `/_internal/replicate/artifact` are capped at four times `MAX_SEGMENT_BYTES` (2 GiB) so a misbehaving peer cannot fill the data PVC. Its batched sibling `/_internal/replicate/artifacts` carries the metadata lane (inline artifacts only) and is capped at 512 items and 8 MiB per request; it answers one outcome per item so a single rejected item does not strand the rest, and a peer that predates the route answers 404, which sends the sender back to the per-artifact route. Backfill listing pages are capped at 32 MiB and 2048 rows, and a bodies response is bounded by the 32 MiB ceiling both sides compile in. When `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND` is positive, Kura also applies a shared per-node bandwidth ceiling to peer artifact body traffic. The effective rate shrinks as public HTTP and gRPC requests are in flight or recent public latency rises above `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS`, so background sync yields network capacity to public cache reads.
- Cache writes are rejected with retryable transport-specific backpressure when memory pressure reaches `Critical`, when the outbox is at `KURA_OUTBOX_MAX_DEPTH`, when the file-descriptor pool is exhausted, or when the data volume has insufficient free space for a new segment.
- Replication delivery is never paused for memory pressure, at any tier and regardless of the raw hard-watermark arm. Because a full outbox rejects cache writes, pausing the drain does not defer work — it strands the queue and ends up rejecting writes, leaving the node divergent from its peers for as long as they can accept its deliveries. The state that walks into the cap is the hard-watermark arm below `Critical`, where writes are still admitted while the drain is held; at `Critical` the write gates already reject before they look at outbox depth, so the outbox is frozen rather than growing. The drain loop is serial and node-wide, so exactly one delivery is in flight regardless of peer count or backlog depth, and it takes no transient reservation — that delivery moves one owned 512 KiB segment-read chunk directly into the peer request body, or for an inline artifact holds the whole value up to the 4 MiB inline ceiling. The usage (metering) outbox has no such coupling and still pauses under critical pressure.
- Kura samples the container charge every 200 milliseconds and removes clean file-backed cache before evaluating pressure, while exporting the complete charge and conventional working set as separate metrics. A file-cache reclaim signal activates on two arms: a working-set arm routed through the hysteretic pressure state machine so it does not flip per sample near the soft watermark, and a raw hard-watermark arm on `memory.current` that intentionally stays steady state on warm serving nodes so they keep trading clean file-cache warmth for request capacity. Either arm makes request paths release completed file ranges without constraining admission. Sampling only drives pressure state, cache trimming, and coarse background load shedding; it never participates in per-request admission arithmetic. Response materialization, foreground uploads, multipart assembly, and peer catch-up transfers share one fair Tokio byte budget derived from the soft-to-hard watermark gap. Response-stream capacity scales with both that gap and the reserve between the hard watermark and runtime limit, allowing request serving to use memory released by pressure-driven cache trimming instead of stopping at a fixed absolute ceiling. Owned permits remain attached to the allocation or transfer that consumed them, and growth while already holding a permit is always non-blocking. A foreground upload reserves a source-plus-destination working set of up to 32 MiB, reduced automatically on smaller memory profiles. Objects larger than the active window, smaller uploads that had to queue, and overlapping foreground uploads synchronize and release completed staging and append-only segment ranges every 8 MiB. Kura closes the synchronized writer before using aligned `DONTNEED` file advice through Rustix, then reopens it in append mode, so cache reclamation cannot invalidate later buffered bytes. Waiting upload admission times out after 30 seconds with `503 Service Unavailable` or gRPC `RESOURCE_EXHAUSTED`. REAPI ByteStream keeps its existing 64 MiB decode limit. A request-body scanner reads every five-byte gRPC envelope header and non-blockingly grows the owned permit to twice the largest message observed before Tonic allocates its retained wire buffer and decoded byte vector. Once the first resource name reveals the blob size, Kura adds only its bounded disk working set. Excess growth returns retryable `RESOURCE_EXHAUSTED` without waiting behind a shared HTTP/2 connection window. Mapped-file serving remains a separate try-only bound over already-resident reclaimable pages and always falls back to streaming. Constrained pressure pauses locally initiated catch-up and snapshot work, but a bounded peer-response pool continues serving backfill reads so the mesh can converge; critical pressure sheds those responses too. Every backpressure response carries a numeric `Retry-After` drawn uniformly between one second and a ceiling that rises with the response-stream queue depth, up to ten seconds when that queue is full, so a fleet shed together does not return together. A joining node retries temporary rate-limit and service-unavailable responses in place, honoring numeric `Retry-After` hints and releasing its memory reservation while it waits. Temporary upload, assembly, and peer-staging files are owned by cancellation-safe cleanup guards, so aborted futures cannot strand disk usage; cancellation cleanup runs on Tokio's blocking pool instead of a runtime worker. The allocator reclaims unused pages on one background thread with a four-second decay, so a quiet node returns memory after a burst without relying on a later request to trigger maintenance.
- Normal artifact and ByteStream readers also use weighted sublimits within that shared transient budget. File-backed artifact and backfill spool responses let the positional read initialize an uninitialized, capacity-bounded vector, move that allocation directly into the response body, and reserve three live buffers sized from 8 KiB to 512 KiB according to the response size. Inline web, replication, and backfill consumers yield reference-counted slices without copying; web responses reserve the complete retained value plus two transport chunks. ByteStream retains its required protocol vector. Materialized Remote Execution responses reserve both their source payload and encoded transport copy. One transport guard follows each permit through encoding and every Hyper-owned byte buffer, so a stalled or cancelled client cannot release capacity early. When the guaranteed response pool is full and memory pressure is normal, public reads may borrow a second bounded tier from unused transient capacity, while retaining one quarter of that capacity for uploads, materialization, and allocator growth. Public reads that cannot reserve either tier promptly degrade to the 8 KiB chunk floor while still charging the 512 KiB per-stream transport send buffer. The degraded queue and slot wait are bounded; when either capacity or transient headroom is exhausted, Kura returns a retryable unavailable response instead of opening an unaccounted stream. Backfill reads never queue, cannot bypass public waiters, and use only their separate reserved progress quantum, leaving the guaranteed foreground capacity for public binary serving.
- Public plaintext HTTP/1 artifact downloads can use the same-port Linux accelerator after the request has been parsed, matched to a known artifact route, authorized, and resolved to a local file. The accelerator owns only a bounded pool of blocking transfer workers and falls back to the normal Axum/Hyper serving path whenever classification is incomplete or unsafe.
- RocksDB column families are configured with explicit level-0 slowdown/stop triggers and pending compaction limits so backlog turns into write-side backpressure instead of unbounded write-buffer growth.
- Inline keyvalue payloads are buffered in memory before being written. Total RAM committed to inline payloads is bounded by `KURA_FILE_DESCRIPTOR_POOL_SIZE * KURA_MAX_KEYVALUE_BYTES`; both knobs are tuned together when sizing per-pod memory.
- On startup, the soft `RLIMIT_NOFILE` is raised to the hard limit so the FD pool, RocksDB file descriptors, and socket budget all share the maximum the container runtime allows.

Auto-derived defaults currently follow these rules:

- `file_descriptor_limit` comes from `RLIMIT_NOFILE` when available, otherwise Kura falls back to a conservative host default.
- `memory_limit_bytes` comes from the exact cgroup memory limit when available, otherwise Kura falls back to physical host memory.
- `cpu_count` comes from detected parallelism via the runtime.
- `KURA_FILE_DESCRIPTOR_POOL_SIZE` is `usable_fds / 8`, clamped to `[64, 256]`, where `usable_fds` is the detected FD limit minus reserved headroom.
- `KURA_SEGMENT_HANDLE_CACHE_SIZE` is `KURA_FILE_DESCRIPTOR_POOL_SIZE / 4`, clamped to `[16, 64]`, and then capped below the FD pool so transient work keeps headroom.
- `KURA_MEMORY_SOFT_LIMIT_BYTES` is `60%` of detected memory, rounded down to MiB boundaries. The wider gap to the hard watermark is the fixed transient-admission budget.
- `KURA_MEMORY_HARD_LIMIT_BYTES` is `85%` of detected memory, rounded down to MiB boundaries. Both watermarks are validated below the exact runtime limit.
- `KURA_SNAPSHOT_CACHE_MAX_BYTES` is `KURA_MEMORY_SOFT_LIMIT_BYTES / 4`, rounded down to MiB boundaries and capped at `256 MiB`.
- `KURA_MANIFEST_CACHE_MAX_BYTES` is `KURA_MEMORY_SOFT_LIMIT_BYTES / 16`, rounded down to MiB boundaries and clamped to `[8 MiB, 64 MiB]`.
- `KURA_METADATA_STORE_MAX_OPEN_FILES` is `usable_fds / 2`, clamped to `[128, 1024]`.
- `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` is `cpu_count`, clamped to `[1, 8]`.
- `KURA_METADATA_STORE_READ_CACHE_BYTES` is `memory_limit_bytes / 32`, rounded down to MiB boundaries and clamped to `[16 MiB, 128 MiB]`.
- `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` follows the same `memory_limit_bytes / 32` rule as the metadata-store read cache.
- `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` is `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES / 4`, rounded down to MiB boundaries and clamped to `[4 MiB, 32 MiB]`.
- `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` is `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES / KURA_METADATA_STORE_WRITE_BUFFER_BYTES`, clamped to `[2, 8]`.
- `KURA_MAX_KEYVALUE_BYTES` defaults to `1048576`, `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` defaults to `5000`, `KURA_DRAIN_COMPLETION_TIMEOUT_MS` defaults to `240000`, `KURA_ACCELERATED_FILE_SERVING_ENABLED` defaults to `true`, `KURA_ACCELERATED_FILE_SERVING_MODE` defaults to `splice`, `KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT` defaults to `32`, `KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES` defaults to `1048576`, `KURA_ACTION_CACHE_EVICTION_CASCADE_ENABLED` defaults to `true`, `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND` defaults to `536870912`, and `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS` defaults to `100`.

A minimal direct-binary deployment still looks like:

```bash
KURA_PORT=4000 \
KURA_INTERNAL_PORT=7443 \
KURA_TENANT_ID=default \
KURA_REGION=eu-central \
KURA_TMP_DIR=/var/cache/kura/tmp \
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

The release version is included as `service.version` in startup and contextual log fields. Operators
can also inspect it directly from a running container or from Prometheus:

```bash
docker compose exec kura /usr/local/bin/kura --version
curl -sS http://127.0.0.1:4000/metrics | grep '^kura_build_info'
```

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

Every cache response carries an `x-request-id`. Kura preserves a valid incoming value or creates a
bounded identifier and adds it to request spans and structured completion events. Successful completion events are disabled by default and can be
sampled with `KURA_REQUEST_LOG_SAMPLE_RATE`. Requests exceeding
`KURA_SLOW_REQUEST_THRESHOLD_MS`, failed streams, and server errors emit rate-limited warnings with
response bytes, time to first byte, total duration, and the serving path. The rate limit uses
constant process memory and reports the number of suppressed events on the next warning.

HTTP request counters keep bounded `route` and `status` labels by using Axum route templates such as `/api/cache/cas/{id}` and folding unmatched paths into `/_unmatched`. Request methods stay on OpenTelemetry spans instead of Prometheus labels. The `kura_http_request_duration_seconds` histogram intentionally has no `route` label and records only public non-probe requests. Keeping route-level latency in Prometheus would multiply every route by every histogram bucket, so route-specific latency belongs in sampled traces instead.

### Node geographic attribution

Each pod resolves its own country and subdivision once at startup and stamps them on every exported OTel span as the `geo.country.iso_code` and `geo.region.iso_code` Resource attributes, alongside the existing `kura.region` (the cloud deployment region, e.g. `fr-par`) and `kura.tenant_id`. The same resolved country/subdivision also lands on the low-cardinality `kura_node_geo_info` Prometheus info metric so Grafana can map serving nodes without parsing traces. This is the serving node's own location; Kura does not geolocate clients, so a request span carries where it was served and never where it came from.

Both values come from deployment configuration alone: resolution is a pure function of the environment, performs no network call, and consults no geographic database. Country resolution chain, tried in order:

1. `KURA_NODE_COUNTRY` env var (2-letter ISO 3166-1 code), set from the datacenter the node runs in.
2. The country prefix of `KURA_NODE_SUBDIVISION`, when only the subdivision is configured (`US-CA` -> `US`).
3. A real country prefix already present in `KURA_REGION` (`fr-par` -> `FR`, `nl-ams` -> `NL`). Continent-style prefixes such as `eu-central` are deliberately not mapped: they name a Tuist region, not a country, and the region they name has changed datacenter before.

Subdivision resolution is `KURA_NODE_SUBDIVISION` (ISO 3166-2 code such as `US-CA`) and nothing else. Neither attribute has a runtime discovery path, so an unconfigured node simply does not stamp it — `geo.region.iso_code` whenever the subdivision is unset, and `geo.country.iso_code` when all three country steps come up empty.

### Disabling OTLP tracing

OTLP tracing is optional. Leaving `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` unset (or empty) makes Kura skip exporter initialization and run without distributed traces — useful in environments without a collector (local kind, isolated edge nodes). Kura records that state once at info level and does not emit missing-layer warnings while handling requests. When the endpoint is set, Kura auto-detects OTLP HTTP vs gRPC from the endpoint shape: `/v1/traces` paths use HTTP, while root collector endpoints such as `http://collector:4317` use gRPC. Helm operators control it by setting `config.telemetry.otlpTracesEndpoint: ""` in a values overlay; the chart only renders the env when the value is non-empty, so an empty overlay disables tracing without crashlooping the pod.

## 📣 Runtime Analytics

Analytics webhooks are a separate optional subsystem for Tuist's current project-scoped cache analytics contract for Xcode, Gradle, and Bazel remote-cache traffic. Bazel's [Build Event Service](https://bazel.build/remote/bep) adds completed-command records separately, so cache observations can be attributed to the corresponding invocation.

After an action-cache result is read or written, Kura also recognizes conventional Bazel test outputs named `test.xml` and `test.log`. It queues only their metadata and re-reads an artifact in a background worker before delivering at most two artifacts per action result to Tuist's test-artifact webhook. Each artifact is limited to 256 KiB. The queue is bounded, delivery is best-effort with bounded retries for temporary upstream responses, and the action-cache request never waits for it. Kura does not make this a durable outbox and Tuist never pulls artifacts back from Kura: losing a delivery is preferable to allowing test reporting to consume unbounded memory, disk, or cache-path latency.

Kura emits cache webhook events only for namespace-scoped Xcode and Gradle HTTP requests, plus Bazel [Remote Execution API](https://github.com/bazelbuild/remote-apis) action-cache and content-addressable-storage requests. It uses the request's `tenant_id` and `namespace_id` as `account_handle` and `project_handle` in the payload. Bazel Build Event Service requests use the `x-tuist-project-handle` metadata set by `tuist bazel setup`; Kura authenticates them with the same account metadata and credential helper as cache traffic. Tenant-scoped cache requests skip analytics until Tuist grows account-scoped binary analytics.

When enabled:

- 🍎 Xcode upload and download events are sent to `/webhooks/cache`
- 🐘 Gradle upload and download events are sent to `/webhooks/gradle-cache`
- 🛠️ completed Bazel invocations are sent to `/webhooks/bazel-invocations`
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

Both surfaces are metered: the HTTP cache path records rollups with `protocol = "http"`, and the REAPI (gRPC) path — `ByteStream` read/write, CAS `BatchReadBlobs`/`BatchUpdateBlobs`, and ActionCache `GetActionResult` (including inlined stdout/stderr/output files) / `UpdateActionResult` — records them with `protocol = "grpc"` and `artifact_kind = "reapi"`, so Bazel and other REAPI clients count toward the same usage surface.

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
- 🚪 optional ingress for the gRPC Remote Execution API
- 🔐 optional peer mTLS for `/_internal/*` traffic via a mounted Kubernetes `Secret`
- 🚦 `/ready` for public readiness and `/up` for liveness (process-local only, never blocking on cluster state; `/status/cluster` serves the node's view of the mesh), with a `preStop` `SIGUSR1` drain hook that removes pods from traffic before `SIGTERM`
- ⏱️ a pod grace period derived from Kura's own drain timeout plus small lifecycle buffers so Kubernetes does not cut shutdown short

Lint and render the chart:

```bash
helm lint ops/helm/kura
helm template kura ops/helm/kura --namespace kura
```

Enable `grpcIngress` when the Bazel Remote Execution API should be reachable outside the cluster. It renders a separate ingress that routes to the service's `grpc` port so you can attach controller-specific gRPC annotations without changing the HTTP API ingress:

```yaml
grpcIngress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  hosts:
    - host: kura-grpc.example.com
      paths:
        - path: /
          pathType: Prefix
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

## 🔐 Cache Authorization

Kura authorizes cache requests against a Tuist server. A token Tuist signs
carries the projects and accounts it grants, so a node holding the verification
key answers most requests from the token alone without leaving the machine.
When a token cannot settle a request — it is opaque, or its grants predate the
project being asked for — the node asks the server.

Core env vars:

- `KURA_AUTH_ENABLED=true`
- `KURA_AUTH_TUIST_URL=https://tuist.dev` — setting this enables authorization on
  its own, and `KURA_AUTH_ENABLED=false` does not override it; a node that knows
  which server to authorize against does not stay open. Unset the URL to run
  without authorization.
- `KURA_AUTH_JWT_PUBLIC_KEY` — the public half of the keypair the server signs
  cache tokens with, as one or more concatenated PEM blocks (`ES256`). A node
  holding it reads those tokens where the request lands and cannot mint one, so
  it is what a node reachable from the internet should be given. During a key
  rotation the value carries both blocks, and the token is tried against each.
- `KURA_AUTH_JWT_SECRET` — the shared-secret alternative, with
  `KURA_AUTH_JWT_ALGORITHM` defaulting to `HS256`. It signs as well as it
  verifies, so a node holding it can mint the tokens it checks; use it only
  where the node and the server are the same trust boundary. Mutually exclusive
  with `KURA_AUTH_JWT_PUBLIC_KEY`.
- Optional `KURA_AUTH_JWT_ISSUER` and `KURA_AUTH_JWT_AUDIENCES` for either
- A token no configured key can read is not refused; the node asks the server
  about it, exactly as a node holding no key at all does
- `KURA_CONTROL_PLANE_CLIENT_ID` and `KURA_CONTROL_PLANE_CLIENT_SECRET`, which
  let a node introspect tokens it cannot verify itself
- `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` (default `3000`) and
  `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` (default `4000`) bound the calls to the
  server. The request budget spans the connect, so keep it the larger of the
  two; a connect budget under about a second fails on a single dropped SYN,
  because TCP does not retransmit one until then.

A node given none of these does not authorize at all, so leaving them unset
serves the cache to anyone who can reach it.

A token the node can verify itself, whose own claims prove the request, is
answered from those claims and never reaches the server. What follows is about
every request the node cannot settle that way: opaque project, account and user
tokens, tokens signed by a key this node does not hold, every request on a node
with no verifier configured, and a verifiable token asking about a target its
own grants do not name — those grants are a snapshot from minting time, and the
server can still allow it through a route they know nothing about.

The cache below still holds what was settled for a verifiable token, which
saves repeating the signature check per request. But asking about one is a
local check rather than a round trip, so none of the outage behaviour applies
to it.

What an evaluation settles is held as one **access level** per credential and
target — `Refused`, `Read` or `ReadWrite`. The level is ordered and write
implies read, so the one confirmed for a read of a project also answers the
write the build issues next, and the other way round. Each fresh answer
**replaces** the entry outright — nothing held earlier survives it — so what
the server takes away stays taken away.

A level asked for an action above it — a write against `Read` — is not refused
outright: the server may still allow it through a route the level knows nothing
about, so the node asks, and the answer replaces the entry. For a short window
after any evaluation the refusal is answered from the entry alone, so a
read-only credential retrying uploads does not hammer the server.

A refusal about one target says nothing about the next, and is held against
that target alone. A refusal about the credential itself — a 401, where the
server says the token is invalid or expired — voids every entry the credential
has at once, so the other projects it covered stop being served immediately.

A credential presented past its own expiry is refused without asking: the
server validates `exp` too and would only answer inactive. That refusal holds
off for the same minute of leeway the verifier allows, so the two cannot
disagree about a credential in its last seconds.

Every level is served for **10 minutes** and then revalidated against the
server, whatever the credential is. That is how long a revocation, a
deactivated user, or a narrowed grant can go unnoticed here. A credential
carrying an `exp` is bounded by it as well — an entry never outlives the
credential's own expiry, and never 25 minutes either — but carrying one is not
a reason to skip revalidation: expiry says when a credential runs out, not
whether it has been withdrawn. The `exp` is read without verifying the
signature, which is safe because it is only read off a credential the server
has just confirmed; a forged one would not have been.

Revalidation is what keeps a control-plane blip off the serving path. A server
that answers is taken at its word either way: its answer replaces the entry,
grant or refusal. A server that does **not** answer knows nothing new about the
credential, so a level that covers the request keeps serving it, up to 25
minutes from the answer that established it and no further — nothing is
written while the server is out of reach, so an outage can never extend its
own cover. A node holding nothing that covers the request still fails closed,
and a credential the server just failed to answer for is left alone for a few
seconds before any request dials again, so an outage costs one probe per
credential per backoff window rather than one per cold target.

Exactly one request asks the server a given question — one credential, one
target — at a time. Concurrent requests for the same question wait for its
answer, so a build starting a hundred requests at once makes one call rather
than a hundred, and a request whose level still answers it is served from that
rather than queueing, so a server that black holes instead of refusing does
not park every request for as long as its timeouts allow. A second project is
a second question and costs its own call, once per revalidation window.

Answers taken from a held entry are counted as
`kura_auth_cache_total{cache="access",result="hit"}` and the ones worked out as
`result="miss"`, with `kura_auth_decisions_total{stage="decide",...}` carrying
what was answered (`allow`, `deny`, or `unavailable`) and how long it took.
Reuse during an outage is `result="stale"`, a trip back to the server for a
held entry is `result="revalidate"`, and an outage the node could not cover is
`kura_auth_decisions_total{stage="authenticate",result="unavailable"}`, logged
with the underlying transport or status error — that stage's other results are
`access` and `deny`.

Everything above is decided against the target a request resolves to, not the
fields it happens to carry, so the two forms below reach the same answer.

Requests carry their target as `tenant_id` and `namespace_id`, also read from
`account_handle` and `project_handle` in the query. A request naming no project
is asking about the account's own cache, which is a different thing from any
project within it: an account grant does not reach a project, and a project
grant does not reach the account. A request naming a tenant this node does not
serve is refused before anything else happens.

When the node cannot reach an answer it denies the request; there is no
configuration that makes it do otherwise.
