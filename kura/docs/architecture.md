# Kura Architecture

This document explains how Kura works, starting from a very high level and going deeper as you read on. Skim the first sections for an overview; read further for the runtime, replication, and rollout details.

## What Kura Is

Kura is a Rust service that builds **low-latency cache meshes**. A mesh is a small set of Kura nodes that each serve cache traffic from local disk and replicate writes to one another in the background. Clients (Bazel, Buck2, Xcode, Gradle, Tuist Module Cache, Nx, Metro) talk to whichever node is closest. Reads come back fast because they are local; writes propagate to peers asynchronously.

The project name comes from the Japanese word `蔵` ("storehouse"). The role of a node fits the name: keep artifacts and metadata stored durably and close at hand.

## The Problem It Solves

Build caches are read-heavy and latency-sensitive. A central cache hundreds of milliseconds away wastes more time than it saves. Kura puts a writable cache node next to each cluster of clients and keeps the nodes loosely consistent in the background. There is no leader, no global lock, and no synchronous fan-out on the hot path.

## High-Level Picture

```
        clients (Bazel/Buck2/Xcode/Gradle/...)
                       │
                       ▼
   ┌──────────────────────────────────────────┐
   │             Kura node (region X)         │
   │                                          │
   │   co-hosted HTTP + gRPC (REAPI)          │
   │            │                             │
   │            ▼                             │
   │   ┌──────────────────────────┐           │
   │   │ request handlers         │           │
   │   └────────┬─────────┬───────┘           │
   │            │         │                   │
   │   ┌────────▼─┐   ┌───▼──────────┐        │
   │   │ RocksDB  │   │ segment files│        │
   │   │ metadata │   │ (blob bodies)│        │
   │   │ + outbox │   │              │        │
   │   └────┬─────┘   └──────────────┘        │
   │        │                                 │
   │        ▼                                 │
   │  outbox worker ──► internal HTTP ──► peers
   │                                          │
   │   membership/discovery worker ◄── peers' │
   │                                  /_internal/status
   └──────────────────────────────────────────┘
```

Each node owns one persistent volume, runs one writer process, and exchanges traffic with peers over a separate **internal plane** that can be optionally protected with mTLS.

## Subsystems And Where They Live

| Concern | Code |
| --- | --- |
| Process entry, server wiring | `src/main.rs`, `src/app.rs` |
| Public HTTP + gRPC handlers, readiness/rollout endpoints | `src/http.rs`, `src/reapi/` |
| Storage (metadata, outbox, segments) | `src/store.rs` |
| Replication (membership, bootstrap, outbox processing) | `src/replication/` |
| Cluster membership and readiness state | `src/state.rs` |
| Traffic state, drain, single-writer fencing | `src/runtime.rs` |
| Configuration + auto-derived defaults | `src/config.rs`, `src/constants.rs` |
| Metrics, traces, logs, error reporting | `src/metrics.rs`, `src/telemetry.rs`, `src/analytics.rs` |
| Usage metering | `src/usage.rs` |
| Optional Lua extension hook | `src/extension.rs` |
| Helm chart, rollout scripts, observability config | `ops/` |
| End-to-end and shell-based tests | `test/e2e/`, `spec/e2e/` |

## Storage Planes

Kura splits durable state into two planes so that the hot path is simple and the cold path can compact freely:

1. **RocksDB** holds metadata: artifact manifests, keyvalue payloads, multipart upload state, namespace tombstones, segment lifecycle records, and the **replication outbox**. Local writes and their outbox entries are committed together, so replication intent is durable as soon as the write is acknowledged. The store reserves outbox slots atomically before that batch, which makes the configured depth a hard process-wide bound even when many write transports race.
2. **Segment files** hold large immutable artifact bodies on disk. The hot path opens segment file descriptors directly, bypassing RocksDB for blob payloads.

The metadata store uses tunable RocksDB budgets (`KURA_METADATA_STORE_*`) that auto-derive from the host's memory and FD limits.

Every public HTTP cache write and read is scoped by `tenant_id`, with an optional `namespace_id`. Namespace-scoped requests land in that namespace directly. Tenant-scoped requests omit `namespace_id` and Kura stores them under an internal empty namespace key, so policy hooks can still distinguish tenant-only traffic from project-like traffic without a special reserved namespace.

## Memory Pressure And Shedding

Kura treats memory as an admission-controlled shared resource, not just a set of independent caches:

- **RocksDB** block cache and write buffers are explicitly budgeted from the host memory limit.
- The in-process **manifest cache** is byte-bounded and trimmed more aggressively as memory pressure rises.
- The action-cache **snapshot cache** is bounded by estimated retained bytes across namespace indexes and encoded full views. Reconciliation admits newest entries first, trims other namespaces before a build, halves retained state under constrained pressure, and drops it under critical pressure.
- The **existence cache** and **segment handle cache** are bounded caches that also shed entries under pressure. The handle cache covers immutable segment and blob files, so repeated reads avoid reopening hot files while staying within the same configured FD budget.
- Public plaintext HTTP/1 artifact downloads can use the same-port Linux accelerator. The public listener first peeks and parses request headers with `httparse` without consuming bytes. Only known artifact GET routes that match the local tenant, pass extension access checks, and resolve to a file-backed local artifact are consumed by the accelerator. Everything else, including HTTPS, HTTP/2, non-GET requests, inline artifacts, cold misses, unsupported routes, saturated accelerator capacity, and non-Linux builds, falls through to the normal Axum/Hyper path. Accelerated transfers are bounded by `KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT` and use `splice` by default, with `sendfile` available as a runtime mode. Accelerated responses are framed with `content-length` and keep the connection alive, so a client can pipeline further requests on the same socket; the accelerator only forces `connection: close` when the client requests it or sends an unconsumed request body, and an idle reused connection is dropped after a bounded keep-alive timeout. A follow-up request that is not accelerable is handed back to the Axum/Hyper path mid-connection without consuming its bytes.
- The normal Axum/Hyper path still serves public HTTPS and fallback HTTP traffic. It prefers mmap-backed `Bytes` chunks for file-backed artifacts only when a bounded memory budget is available **and the region is already resident in the page cache** (checked with `mincore`), so hot fallback responses avoid copying artifact bytes into heap buffers. Hot mmap responses are yielded in 1 MiB chunks to keep Hyper body overhead low. Cold or budget-constrained reads fall back to the streaming reader path, which isolates blocking reads with `spawn_blocking` and keeps each read at 512 KiB. REAPI ByteStream reads stay **streaming**, so they do not materialize whole artifacts in memory.
- REAPI surfaces that must build whole responses in memory (`BatchReadBlobs`, `GetActionResult` inline expansions, action-cache proto loads) use two gates:
  1. a **per-request materialization budget** that shrinks from normal → constrained → critical memory pressure
  2. a **shared concurrent materialization pool** across the node whose byte permits stay attached to the response until its body is dropped, so slow clients cannot leave many fully materialized responses unaccounted

The pressure sensor reads the container's full cgroup charge every 200 milliseconds and only publishes atomic state. A separate one-second actuator samples the detailed heap/file/kernel breakdown and performs lock-taking cache cleanup. This separation keeps slow cache locks or extension cleanup from delaying the next pressure observation. A transient byte ledger combines the latest cgroup charge with predicted bytes for admitted work: foreground materialization and disk-backed uploads may reserve up to the hard watermark, while background snapshot and bootstrap work may reserve only below the soft watermark. The controller establishes a post-store-open baseline before listeners start and refreshes the kernel charge as each upload reservation is released, so fast completions cannot repeatedly spend stale headroom between sensor samples. The allocator runs one background page-reclamation thread with a four-second dirty and muzzy-page decay; startup fails if that configuration is not active, preventing unused allocator pages from holding an idle node in critical pressure after a burst.

Disk-backed foreground writes use a source-plus-destination lease of up to 32 MiB. A body larger than 16 MiB uses an 8 MiB synchronized file-cache window in both its temporary staging file and append-only segment. A smaller write keeps its warm staging pages on the uncontended path, but switches to the same bounded policy after it has queued for headroom or overlaps another foreground reservation. The one admission decision follows the request through staging, multipart assembly when applicable, and segment persistence, so the 200 millisecond pressure sample cannot make the two copies disagree. At each completed range Kura synchronizes and closes the writer before advising the kernel to release clean pages, then resumes with a fresh append-only descriptor; this preserves later buffered bytes and the append-only segment invariant. Multipart parts synchronize and release their clean pages while waiting for completion, and assembly releases each input part after it is copied. ByteStream preserves the existing 64 MiB decode limit with an admission body in front of Tonic. The body scans every five-byte gRPC envelope header, including headers split across transport frames or following another message in the same frame, and non-blockingly grows the stream lease to twice the largest encoded message observed before forwarding that header to Tonic. After the first resource name reveals the blob size, the handler adds `2 * min(blob size, 16 MiB)` for staging and segment file cache. The lease therefore follows actual chunk size instead of reserving 160 MiB for every write, while a real 64 MiB message is still fully covered. Failed growth surfaces `RESOURCE_EXHAUSTED` immediately and never waits while consuming shared HTTP/2 connection flow-control. Other foreground uploads retain the 30-second admission deadline so bounded work can queue briefly without waiting indefinitely.

When a request would exceed either REAPI response gate, Kura returns `RESOURCE_EXHAUSTED` instead of continuing toward an out-of-memory path. Upload admission waits for bounded headroom and returns `RESOURCE_EXHAUSTED` or `503 Service Unavailable` only when its deadline expires. Under **constrained** pressure Kura pauses new bootstrap and snapshot work and halves retained optional caches. Under **critical** pressure it trims opportunistic caches to zero, checks pressure before every outbox message so the durable backlog stays queued, and clears extension authorization and authentication caches because they are performance state, not correctness state.

## Replication Model

Replication is **leaderless and eventually consistent**:

- Every node is a writer for its own clients.
- A successful local write enqueues an `OutboxMessage` in RocksDB inside the same atomic batch as the metadata commit.
- A background **outbox worker** drains the queue and PUTs each message to the corresponding peer over the internal plane. On success, the message is deleted; on failure it stays queued and the worker retries. Messages whose target is absent from the node's current peer set are **dropped immediately** (observable as `dropped_stale_target` replication results): the fetched peer view is authoritative and the control plane withholds a peer only after a full staleness window of missed heartbeats, so the removal is deliberate — and a peer that later rejoins does so through a recovery re-enrollment that re-bootstraps the full dataset, so dropped deltas are recovered. Targets known only through discovery (in-cluster siblings, cross-region pods) are treated like the static seeds and never pruned within a process lifetime: their absence usually means a network flap rather than departure, and nothing re-bootstraps them afterwards. The protection is process-scoped — a genuinely removed pod (scale-down, region move) is never rediscovered after the observer's next restart, and since enqueues stop within one membership tick of unreachability, its small frozen backlog is dropped after the next deploy. An empty peer view never prunes — it means the node has no view (control plane unreachable), not that every peer left.
- Large peer artifact body transfers can be application-throttled with `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND`. The limiter is shared per node across live replication uploads, replication ingests, and bootstrap artifact fetches/responses. The configured value is a ceiling; the effective sync rate is divided by the larger of `public_inflight + 1` and the recent public request latency EWMA over `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS`. The latency EWMA is sampled at time-to-first-byte (when the response is ready to start streaming), not at body completion, so large but healthy downloads do not register as latency and over-throttle sync; their concurrency is already captured by `public_inflight`. Public inflight includes non-probe public HTTP requests plus gRPC cache RPCs. Internal replication and probe requests do not count as public load. This lets sync work use its full budget while the node is quiet and back off automatically when public cache traffic is active or slow.

Two observability surfaces support capacity and sharding decisions: `kura_public_request_latency_seconds` is a histogram of time-to-first-byte for public requests across both transports (`transport` is `http` or `grpc`, labeled by `route`), and `kura_artifact_egress_throughput_bytes_per_second` is a histogram of achieved per-response egress throughput by `producer`. Together with the aggregate `kura_artifact_egress_bytes_total` rate they indicate when a region is bandwidth-bound and a good candidate for sharding across more primary pods.
- Conflicts are resolved by `version_ms` (last-writer-wins per key); stale applies are rejected with `ArtifactApplyOutcome::IgnoredStale`. The apply path takes a per-key write lock so that concurrent applies of the same key serialize: the first commits the manifest and the rest re-read it and short-circuit to `IgnoredStale` rather than each appending their own copy to a segment. Without it, simultaneous applies of one key leave all but the last copy orphaned on disk.

Newly joined nodes catch up by **bootstrapping from a peer**: paginated manifest and tombstone fetches followed by lazy artifact body fetches. Bootstrap re-uses the same apply paths as live replication, so the same conflict rules apply. A fresh node bootstraps from every known peer concurrently (so it captures artifacts that exist on only one peer), which means the same artifact is offered by several peers at once. Three layers keep that overlap bounded: a per-artifact **fetch gate** single-flights the body download so only the first peer-task to claim a key transfers it while the rest re-check presence and skip the network; a live-memory reservation admits only the transfer windows that fit below the soft watermark; and the per-key **apply lock** is the last-line guarantee that even a body that does get fetched twice is written to a segment only once. Large transfers do not reserve their full object size because a valid object may approach the container limit. Instead, once pressure rises, completed temporary-file and append-only segment ranges are synchronized and released from Linux file cache in bounded intervals before the stream waits for recovery. The cache advice is an optional optimization and never changes storage correctness.

Before walking a peer's manifests, bootstrap runs **range-digest anti-entropy** so the walk costs O(delta) rather than O(peer dataset). The manifests column family is a sorted keyspace over `artifact_id` (a content/storage hash, identical across nodes for identical content); both nodes summarize it as per-prefix-bucket digests (`GET /_internal/bootstrap/digest?prefix_len=3` → 4096 buckets of `(prefix, count, hash)`, where the hash folds the sorted `(artifact_id, version_ms)` pairs so adds, removes, and version bumps all flip a bucket). The joining node diffs the peer's digest against its own and enumerates only the mismatching buckets — scoping the existing paginated walk to each divergent prefix range (`&prefix=`). For a mostly-in-sync pair this collapses a full-keyspace page walk into one digest exchange plus a handful of small range walks. The endpoint is additive and negotiated: a peer that 404s it (one version behind during a rollout) falls back to the full walk, so a mixed-version mesh stays correct. The digest only decides *which ranges to enumerate*; apply semantics are unchanged, so a digest bug can at worst cause an unnecessary walk, never a wrong apply.

A per-peer bootstrap runs under a **no-progress watchdog** rather than a fixed total-runtime cap. `KURA_BOOTSTRAP_TIMEOUT_MS` is the maximum time the bootstrap may go *without* forward progress (a fetched page or applied artifact); a bootstrap that keeps advancing runs to completion however long that takes, and only a genuinely stalled one is abandoned and retried. A single wall-clock cap could never let a large cold pull finish — it would be killed and restarted from scratch every window — so a node whose backlog exceeds one window's worth of transfer would stay `NotReady` indefinitely.

See `src/replication/mod.rs` for the membership/outbox/bootstrap loops, and `src/replication/operation.rs` + `outbox_message.rs` for the message types.

## Discovery And Membership

A node finds peers in three ways:

1. **Static seeds** from `KURA_PEERS`. Static config is immutable for the process lifetime, so it carries **platform-stable peers only** (the managed regions' public peer gateways); volatile membership lives in the dynamic layer below.
2. **Control-plane dynamic membership** (`src/mesh_heartbeat.rs`): enrolled self-hosted nodes send a mesh heartbeat every ~60s (cadence server-advertised) whose response carries the current peer list; managed pods fetch the same view read-only when `KURA_MESH_PEERS_SYNC` is set, with serving gated on the first successful fetch (a pod booting blind would accept writes without enqueuing replication for peers it cannot see). Additions **and removals** propagate at heartbeat cadence with no restart; a failed heartbeat keeps the last-known view, so a degraded control plane can never shrink the mesh.
3. **DNS-based discovery** via `KURA_DISCOVERY_DNS_NAME`, which resolves to the addresses of the other pods (typical when running as a Kubernetes `StatefulSet` behind a headless service).

A `spawn_membership_task` loop polls each candidate's `GET /_internal/status` every two seconds. Only peers that respond with the same `tenant_id` and a different `node_url` are admitted as members. The local node never lists itself.

Mesh **membership itself** is control-plane state for enrolled nodes: a node that stops sending mesh heartbeats is deactivated (withheld from every peer's view) and its row is purged once its peer certificate can no longer be valid. Heartbeats never create or restore membership — a withheld node is answered `mesh_member: false` and recovers with a **recovery re-enrollment** (backoff-limited), which reactivates or recreates its membership server-side, clears local bootstrap progress, and takes the node out of serving until it has re-pulled the full dataset: the writes it missed while out of the mesh were never enqueued for it (replication targets are computed at write time), so only a full re-bootstrap can reconcile the gap.

Each tick produces a `MembershipUpdate` and feeds it into `ReadinessState` (`src/state.rs`). The state tracks:

- the set of `known_peers` (peers that responded successfully),
- which peers we have **bootstrapped** from,
- which bootstraps are currently **inflight**,
- a monotonically increasing **generation** that bumps whenever the membership topology changes,
- and a short **settle window** after each generation change.

`initial_discovery_completed` only flips once we have actually observed a successful peer status check (or there are no discovery targets at all). This avoids promoting a node to "ready" when the seed peers were transiently unreachable.

## Traffic Lifecycle

A node moves through three explicit traffic states (`src/runtime.rs`):

```
        ┌──────────┐  membership generation     ┌──────────┐
        │          │   advances or restart      │          │
        │ joining  │ ◄──────────────────────────│ serving  │
        │          │                            │          │
        └────┬─────┘                            └─────┬────┘
             │ all known peers bootstrapped,          │
             │ discovery observed, settle window      │
             │ elapsed                                │
             ▼                                        ▼
        ┌──────────┐         drain request      ┌──────────┐
        │ serving  │ ─────────────────────────► │ draining │
        └──────────┘                            └──────────┘
```

- **`joining`** — public reads/writes are accepted but `/ready` returns `503` until bootstrap completes for every known peer. This keeps load balancers from routing traffic to a half-warm pod.
- **`serving`** — `/ready` returns `200`. Public APIs handle traffic normally.
- **`draining`** — public HTTP rejects new requests and stops reusing HTTP/1.1 connections; established HTTP/2 connections (gRPC included) receive a GOAWAY so channels finish in-flight streams and reconnect elsewhere. Inflight work continues until a shared **drain deadline** (`KURA_DRAIN_COMPLETION_TIMEOUT_MS`) elapses.

Independent of draining, the co-hosted listener's hyper path recycles every connection after `CONNECTION_MAX_AGE` (300s): the server sends GOAWAY and allows in-flight streams `CONNECTION_MAX_AGE_GRACE` (900s) to finish before severing. Without recycling, a long-lived Bazel channel would pin to a demoted-but-alive NodePort primary indefinitely after failover. Both public listeners — plaintext and TLS, with acceleration on or off — share this per-connection serving path, so recycling and drain GOAWAY apply uniformly; the internal mTLS peer listener is a separate plane with its own lifecycle.

The action cache also serves an **instance-wide snapshot** through a reserved action key (`tuist-actioncache-snapshot/v2`, intercepted by digest comparison inside `GetActionResult` — no dedicated RPC): the response inlines the namespace's complete key→value map as a deduplicated node table plus per-key node-index lists and a write-time watermark, so a cold client primes every association in one round trip and fetches content through ordinary batched blob reads. Serving is backed by an incrementally maintained per-namespace index (bounded, LRU): reconciliation runs as a detached task shared by every concurrent request (a client or gateway that gives up on a slow first build cannot throw the work away — the build completes and caches regardless, and the next request serves from memory) and diffs the cached index against the newest slice of the action-cache keyspace; a request with no cached index waits only briefly for the build before answering `UNAVAILABLE` (the client stays on the per-key path and refetches shortly — pinning requests to a long first build walked every one of them into its deadline). Enumeration reads a dedicated `action_cache_index` column family ordered newest-first by write time (maintained at publish/delete, lazily backfilled per namespace with one legacy full scan) so a reconcile touches at most its entry cap rather than the whole namespace — the scan keeps only the most recent entries by write time, bounding the build's memory the way the byte ceiling bounds the response; only new-or-changed entries read their stored ActionResult — every referenced blob is presence-gated by manifest existence, which tracks eviction exactly, and the node table is compacted once entry churn strands enough unreferenced nodes. A `tuist-snapshot-after:<watermark>` hint in `inline_output_files` returns a delta of entries written at or after the client's watermark (inclusive — millisecond versions are not unique, and re-sent boundary entries merge idempotently); deltas only add, so clients periodically refetch the full view to pick up retractions. The payload is capped at 48 MiB: the full view encodes newest-first (the ceiling sheds the oldest keys — a recency window) while a delta encodes oldest-first with the watermark set to the newest entry actually included, so an oversized delta paginates across refreshes instead of skipping what it dropped. A server without the feature answers a plain not-found the client degrades from — safe under mixed-version rollouts. Bump the key's version suffix on any encoding change.

Action-cache entries are also the one artifact class with their own lifecycle: clients publish new keys on every source change and the tiny records never face segment capacity pressure, so without intervention a namespace's keyspace grows forever. Two mechanisms bound it, both node-local (peers apply the same rules over the replicated `version_ms` and converge on their own): the snapshot serve path cascade-deletes entries whose blobs were evicted (unserveable by construction; a grace window spares young entries whose blobs may still be mid-replication), and a periodic background sweep expires entries whose write time predates the TTL — an expired entry that is still used costs its next cold reader one recompile + republish, which refreshes it fleet-wide.

The REAPI gRPC services (`src/reapi/mod.rs`) are mounted into the co-hosted listener rather than a dedicated gRPC server (`reapi::routes` returns an `axum::Router` that `run_with_config` merges with the HTTP router). The listener advertises raised HTTP/2 flow-control windows — a 4 MiB stream window and a 16 MiB connection window — so a single large `ByteStream.Write` is not throttled to roughly `window / RTT` under WAN latency (without them the kura hop becomes the next bottleneck after the gateway nginx window). The window is FIXED, never adaptive: hyper's adaptive flow control would override the fixed size and ramp a single stream up from ~64 KiB, halving single-stream upload throughput under WAN latency. A per-upload stall timeout (60s, keyed on byte progress so trickled keepalive frames cannot hold a stalled stream open) reclaims a vanished or stalled writer without cutting an upload that keeps making progress. Temporary files also carry drop guards, so transport cancellation and bootstrap watchdog cancellation schedule partial-file removal on Tokio's blocking pool even when they drop a future before its asynchronous cleanup path runs.

`/up` is a liveness signal that does not depend on any of this — it stays healthy as long as the process is alive.

## Single-Writer Fencing

Each PVC is owned by exactly one Kura process. On startup, `DataDirLock` (`src/runtime.rs`) takes an OS file lock on `.kura.writer.lock` inside `KURA_DATA_DIR`. If another process holds the lock, startup fails fast. Public readiness depends on the lock being held, so a node that loses the lock cannot serve traffic.

The Kubernetes layer reinforces this with `ReadWriteOncePod` PVC access by default; the app-level lock is the source of truth and works even when the CSI driver only supports `ReadWriteOnce`.

## Rollouts

Rollouts are deliberately conservative because each node is stateful and serves cache traffic that should not regress to misses during an upgrade.

The pieces:

- A pod's `preStop` hook sends `SIGUSR1` to start drain. The pod stays alive long enough to finish inflight work, then exits.
- `terminationGracePeriodSeconds` is computed from the application's own drain timeout plus small lifecycle buffers, so Kubernetes never cuts shutdown short.
- A generic **rollout gate** (`ops/rollout/gate.sh`) polls each node's `/status/rollout` and only advances when every node reports the same membership generation, all are back in `serving`, ring size matches, no bootstrap is inflight, the outbox is near baseline, no node is under critical memory pressure, and there is no new file-descriptor timeout activity.
- A **Kubernetes adapter** (`ops/helm/kura/rollout.sh`) stages the new revision behind a `StatefulSet` partition, rolls the highest ordinal first, and delegates health gating to the generic gate. The adapter is a thin transport layer; it does not own rollout semantics.
- An **adjacent-version compatibility harness** (`test/e2e/kura_compatibility_rollout.sh`) validates `PREVIOUS_REF → HEAD → PREVIOUS_REF` on the same persistent Docker volumes for the artifact CAS path.

The rollout gate explicitly assumes only that it can fetch `/status/rollout` from each node. It does not depend on Kubernetes probes or Prometheus.

## Observability

Each node exposes:

- Prometheus metrics on `/metrics` (replication latency, FD pressure, manifest cache, RocksDB internals, outbox depth, traffic state, rollout-relevant counters).
- HTTP request counters use bounded route-template and status labels, request methods stay on spans, client countries are counted separately on `kura_http_client_requests_total`, and `kura_http_request_duration_seconds` aggregates public non-probe latency without a route label to avoid multiplying route cardinality by histogram buckets.
- OpenTelemetry traces for replication and request handling.
- Control-plane usage metering for public cache traffic when configured through `KURA_CONTROL_PLANE_URL` and client credentials. Kura aggregates bytes and request counts into bounded in-memory windows, persists closed windows into a dedicated RocksDB usage outbox, and pushes batches to `/_internal/kura/usage`. Delivery pauses under critical memory pressure and is at least once, with deterministic event ids for control-plane deduplication. Both transports are metered and tagged by `protocol`: the HTTP cache path emits `protocol = "http"`, and the REAPI (gRPC) path emits `protocol = "grpc"` with `artifact_kind = "reapi"`. A batch RPC (`BatchReadBlobs`/`BatchUpdateBlobs`) books one request carrying the aggregate bytes, matching the one-request-per-call accounting of the HTTP and ByteStream paths, and re-uploads of an already-present blob are not billed.
- Client geographic attribution sourced from the `X-Forwarded-For` / `X-Real-IP` headers and resolved against the DB-IP Lite City MMDB vendored into the container image at `/opt/geoip/dbip-city-lite.mmdb` (`src/geoip.rs`). Country (ISO 3166-1) lands on both the `kura_http_client_requests_total` metric (as the `client_country` label) and `http.request` spans (as `geo.country.iso_code`); subdivision (ISO 3166-2) lands on spans only (as `geo.region.iso_code`), deliberately kept off metrics to bound label cardinality. Span and Resource attributes follow the OpenTelemetry `geo.*` semantic conventions. On by default; soft-fails when the database file is absent. A background task refreshes the in-memory copy every `KURA_GEOIP_REFRESH_INTERVAL_SECS` seconds (default `86400`, `0` disables) with download/decompress sizes capped (128 MiB / 256 MiB) to stay within Kura's resource discipline.
- Node geographic attribution: each pod resolves its own country and subdivision at startup (`src/node_location.rs`), probing the egress IP only when the operator overrides do not already cover the missing fields. Country falls back to an explicit mapping for the synthetic deployment labels we use today (`eu-central` -> `DE`, `us-east` / `us-west` -> `US`) or to a real country prefix already embedded in the region label (`fr-par` -> `FR`, `nl-ams` -> `NL`). The result stamps `geo.country.iso_code` and `geo.region.iso_code` on the OTel Resource (next to the unchanged `kura.region` cloud deployment region) so every span carries them, and also lands on the low-cardinality `kura_node_geo_info` metric for Grafana maps. Combined with the request-side `geo.country.iso_code` / `geo.region.iso_code`, traces have both endpoints needed to compute geographic distance.
- Structured logs intended for Loki/Promtail.
- Optional Sentry forwarding for panics and `tracing::error!` events.

Helm and the local docker-compose stack ship a complete Grafana/Prometheus/Loki/Tempo setup. See `ops/AGENTS.md` for layout.

## Configuration Surface

All configuration is environment-driven (`src/config.rs`). The full table lives in [`README.md`](../README.md#-runtime-model-and-limits). Highlights:

- Required identity and addressing: `KURA_TENANT_ID`, `KURA_REGION`, `KURA_NODE_URL`, `KURA_PORT`, `KURA_INTERNAL_PORT`, `KURA_DATA_DIR`, `KURA_TMP_DIR`.
- Co-hosted HTTP + gRPC surface: HTTP cache and the h2c REAPI gRPC service share one listener, dispatched by request path (gRPC service paths route to REAPI via `reapi::routes`, everything else to the HTTP router), so a single client-facing URL speaks both protocols. It serves plaintext on `KURA_PORT` and — when `public_tls` (`KURA_PUBLIC_TLS_*`) is configured — TLS on `KURA_HTTPS_PORT`, ALPN-negotiated (`h2` for gRPC, `http/1.1` for HTTP). The plaintext listener runs through the accelerated server, so HTTP/1 artifact GETs get the sendfile/splice fast path while gRPC (h2c) and other non-accelerable requests fall through to hyper; the TLS listener uses the plain hyper path (TLS is incompatible with sendfile). Both use the fixed REAPI-sized HTTP/2 windows so co-hosted uploads are not throttled.
- Peer plane: `KURA_PEERS`, `KURA_DISCOVERY_DNS_NAME`, optional `KURA_INTERNAL_TLS_*` for peer mTLS.
- Resource budgets: file-descriptor pool, memory soft/hard limits, tmp staging, manifest cache, snapshot cache, and RocksDB write buffer pool, all with defaults derived from Kura's bounded runtime model. Temporary writers share one byte reservation ledger, and cancellation keeps its reservation until the cleanup unlink completes.
- Peer sync bandwidth: `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND` sets the aggregate peer artifact body traffic ceiling per node when set above `0`; Kura adapts the effective rate downward under public HTTP or gRPC load, and `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS` controls the latency target for additional backoff.
- Same-port accelerated file serving: `KURA_ACCELERATED_FILE_SERVING_ENABLED`, `KURA_ACCELERATED_FILE_SERVING_MODE`, `KURA_ACCELERATED_FILE_SERVING_MAX_CONCURRENT`, and `KURA_ACCELERATED_FILE_SERVING_CHUNK_BYTES` bound the Linux plaintext HTTP/1 artifact fast path while preserving the Axum/Hyper fallback path on the same public port.
- Drain timing: `KURA_DRAIN_COMPLETION_TIMEOUT_MS`.

When budget vars are unset Kura inspects `RLIMIT_NOFILE`, the cgroup memory limit, and detected CPU count to pick safe defaults.

## Where To Read Next

- For protocol surfaces (REAPI, Xcode, Gradle, Module Cache, Nx, Metro), start in `src/http.rs` and `src/reapi/mod.rs`.
- For the storage layer, `src/store.rs` is the single entry point.
- For replication invariants and bootstrap retry behavior, see `src/replication/mod.rs` and `src/state.rs`.
- For the Helm chart and rollout scripts, see `ops/helm/kura/` and `ops/rollout/gate.sh`.
- For end-to-end behavior, the shellspec suite under `spec/e2e/` exercises the live stack.
