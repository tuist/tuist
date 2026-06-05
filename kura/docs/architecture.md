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
   │   public HTTP   gRPC (REAPI)             │
   │       │            │                     │
   │       ▼            ▼                     │
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

1. **RocksDB** holds metadata: artifact manifests, keyvalue payloads, multipart upload state, namespace tombstones, segment lifecycle records, and the **replication outbox**. Local writes and their outbox entries are committed together, so replication intent is durable as soon as the write is acknowledged.
2. **Segment files** hold large immutable artifact bodies on disk. The hot path opens segment file descriptors directly, bypassing RocksDB for blob payloads.

The metadata store uses tunable RocksDB budgets (`KURA_METADATA_STORE_*`) that auto-derive from the host's memory and FD limits.

Every public HTTP cache write and read is scoped by `tenant_id`, with an optional `namespace_id`. Namespace-scoped requests land in that namespace directly. Tenant-scoped requests omit `namespace_id` and Kura stores them under an internal empty namespace key, so policy hooks can still distinguish tenant-only traffic from project-like traffic without a special reserved namespace.

## Memory Pressure And Shedding

Kura treats memory as an admission-controlled shared resource, not just a set of independent caches:

- **RocksDB** block cache and write buffers are explicitly budgeted from the host memory limit.
- The in-process **manifest cache** is byte-bounded and trimmed more aggressively as memory pressure rises.
- The **existence cache** and **segment handle cache** are bounded caches that also shed entries under pressure.
- Public HTTPS accepts HTTP/2 for multiplexed artifact downloads. Public HTTP artifact reads prefer mmap-backed `Bytes` chunks for file-backed artifacts only when a bounded memory budget is available **and the region is already resident in the page cache** (checked with `mincore`), so serving hot artifacts is zero-copy and never faults disk I/O onto the async workers. Cold or budget-constrained reads fall back to the streaming reader path, which isolates blocking reads with `spawn_blocking`. REAPI ByteStream reads stay **streaming**, so they do not materialize whole artifacts in memory.
- REAPI surfaces that must build whole responses in memory (`BatchReadBlobs`, `GetActionResult` inline expansions, action-cache proto loads) use two gates:
  1. a **per-request materialization budget** that shrinks from normal → constrained → critical memory pressure
  2. a **shared concurrent materialization pool** across the node, so many concurrent inline reads cannot oversubscribe memory together

When a request would exceed either REAPI gate, Kura returns `RESOURCE_EXHAUSTED` instead of continuing toward an OOM path. Under **critical** pressure it also pauses optional background work, trims opportunistic caches to zero, and clears extension authz/authn caches because they are performance state, not correctness state.

## Replication Model

Replication is **leaderless and eventually consistent**:

- Every node is a writer for its own clients.
- A successful local write enqueues an `OutboxMessage` in RocksDB inside the same atomic batch as the metadata commit.
- A background **outbox worker** drains the queue and PUTs each message to the corresponding peer over the internal plane. On success, the message is deleted; on failure it stays queued and the worker retries.
- Large peer artifact body transfers can be application-throttled with `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND`. The limiter is shared per node across live replication uploads, replication ingests, and bootstrap artifact fetches/responses. The configured value is a ceiling; the effective sync rate is divided by the larger of `public_inflight + 1` and the recent public request latency EWMA over `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS`. Public inflight includes non-probe public HTTP requests plus gRPC cache RPCs. Internal replication and probe requests do not count as public load. This lets sync work use its full budget while the node is quiet and back off automatically when public cache traffic is active or slow.
- Conflicts are resolved by `version_ms` (last-writer-wins per key); stale applies are rejected with `ArtifactApplyOutcome::IgnoredStale`.

Newly joined nodes catch up by **bootstrapping from a peer**: paginated manifest and tombstone fetches followed by lazy artifact body fetches. Bootstrap re-uses the same apply paths as live replication, so the same conflict rules apply.

See `src/replication/mod.rs` for the membership/outbox/bootstrap loops, and `src/replication/operation.rs` + `outbox_message.rs` for the message types.

## Discovery And Membership

A node finds peers in two ways:

1. **Static seeds** from `KURA_PEERS`.
2. **DNS-based discovery** via `KURA_DISCOVERY_DNS_NAME`, which resolves to the addresses of the other pods (typical when running as a Kubernetes `StatefulSet` behind a headless service).

A `spawn_membership_task` loop polls each candidate's `GET /_internal/status` every two seconds. Only peers that respond with the same `tenant_id` and a different `node_url` are admitted as members. The local node never lists itself.

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
- **`draining`** — public HTTP rejects new requests and closes HTTP/1.1 connections; gRPC stops accepting new RPCs and ages out long-lived connections. Inflight work continues until a shared **drain deadline** (`KURA_DRAIN_COMPLETION_TIMEOUT_MS`) elapses.

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
- Control-plane usage metering for public cache traffic when configured through `KURA_CONTROL_PLANE_URL` and client credentials. Kura aggregates bytes and request counts into bounded in-memory windows, persists closed windows into a dedicated RocksDB usage outbox, and pushes batches to `/_internal/kura/usage`. Delivery pauses under critical memory pressure and is at least once, with deterministic event ids for control-plane deduplication.
- Client geographic attribution sourced from the `X-Forwarded-For` / `X-Real-IP` headers and resolved against the DB-IP Lite City MMDB vendored into the container image at `/opt/geoip/dbip-city-lite.mmdb` (`src/geoip.rs`). Country (ISO 3166-1) lands on both the `kura_http_client_requests_total` metric (as the `client_country` label) and `http.request` spans (as `geo.country.iso_code`); subdivision (ISO 3166-2) lands on spans only (as `geo.region.iso_code`), deliberately kept off metrics to bound label cardinality. Span and Resource attributes follow the OpenTelemetry `geo.*` semantic conventions. On by default; soft-fails when the database file is absent. A background task refreshes the in-memory copy every `KURA_GEOIP_REFRESH_INTERVAL_SECS` seconds (default `86400`, `0` disables) with download/decompress sizes capped (128 MiB / 256 MiB) to stay within Kura's resource discipline.
- Node geographic attribution: each pod resolves its own country and subdivision at startup (`src/node_location.rs`), probing the egress IP only when the operator overrides do not already cover the missing fields. Country falls back to an explicit mapping for the synthetic deployment labels we use today (`eu-central` -> `DE`, `us-east` / `us-west` -> `US`) or to a real country prefix already embedded in the region label (`fr-par` -> `FR`, `nl-ams` -> `NL`). The result stamps `geo.country.iso_code` and `geo.region.iso_code` on the OTel Resource (next to the unchanged `kura.region` cloud deployment region) so every span carries them, and also lands on the low-cardinality `kura_node_geo_info` metric for Grafana maps. Combined with the request-side `geo.country.iso_code` / `geo.region.iso_code`, traces have both endpoints needed to compute geographic distance.
- Structured logs intended for Loki/Promtail.
- Optional Sentry forwarding for panics and `tracing::error!` events.

Helm and the local docker-compose stack ship a complete Grafana/Prometheus/Loki/Tempo setup. See `ops/AGENTS.md` for layout.

## Configuration Surface

All configuration is environment-driven (`src/config.rs`). The full table lives in [`README.md`](../README.md#-runtime-model-and-limits). Highlights:

- Required identity and addressing: `KURA_TENANT_ID`, `KURA_REGION`, `KURA_NODE_URL`, `KURA_PORT`, `KURA_GRPC_PORT`, `KURA_INTERNAL_PORT`, `KURA_DATA_DIR`, `KURA_TMP_DIR`.
- Peer plane: `KURA_PEERS`, `KURA_DISCOVERY_DNS_NAME`, optional `KURA_INTERNAL_TLS_*` for peer mTLS.
- Resource budgets: file-descriptor pool, memory soft/hard limits, manifest cache, RocksDB write buffer pool, all with `auto` defaults derived from the host.
- Peer sync bandwidth: `KURA_REPLICATION_BANDWIDTH_LIMIT_BYTES_PER_SECOND` sets the aggregate peer artifact body traffic ceiling per node when set above `0`; Kura adapts the effective rate downward under public HTTP or gRPC load, and `KURA_REPLICATION_PUBLIC_LATENCY_TARGET_MS` controls the latency target for additional backoff.
- Drain timing: `KURA_DRAIN_COMPLETION_TIMEOUT_MS`.

When budget vars are unset Kura inspects `RLIMIT_NOFILE`, the cgroup memory limit, and detected CPU count to pick safe defaults.

## Where To Read Next

- For protocol surfaces (REAPI, Xcode, Gradle, Module Cache, Nx, Metro), start in `src/http.rs` and `src/reapi/mod.rs`.
- For the storage layer, `src/store.rs` is the single entry point.
- For replication invariants and bootstrap retry behavior, see `src/replication/mod.rs` and `src/state.rs`.
- For the Helm chart and rollout scripts, see `ops/helm/kura/` and `ops/rollout/gate.sh`.
- For end-to-end behavior, the shellspec suite under `spec/e2e/` exercises the live stack.
