---
{
  "title": "Self-hosted cache",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "Deploy self-hosted cache nodes and connect them to Tuist."
}
---

# Self-hosted cache {#self-hosted-cache}

Self-hosted cache nodes let you keep build artifacts and cache metadata close to the machines that produce and consume build outputs. Use them when cache latency matters across CI, developer offices, remote workstations, or regional compute clusters, while keeping endpoint discovery centralized through Tuist.

The goal is low-latency caching everywhere, not only in the one environment where a central cache happens to be nearby. Each cache node serves reads and writes from local disk, while the mesh replicates artifacts and metadata between peers so other locations can benefit from the same cache over time.

> [!NOTE]
> Tuist's self-hosted cache nodes are powered by [Kura](https://github.com/tuist/tuist/tree/main/kura), Tuist's decentralized cache mesh. Kura is the data plane for cache nodes: it serves cache reads and writes, stores local state on disk, and replicates artifacts and metadata to peer nodes.

## How self-hosted cache fits with Tuist {#how-self-hosted-cache-fits-with-tuist}

The Tuist server tells clients which cache endpoints to use. This keeps endpoint discovery centralized while allowing the cache itself to stay decentralized and close to the compute that needs it.

## Build a cache mesh {#build-a-cache-mesh}

A self-hosted cache works best as a small mesh of nodes that can reach each other on Kura's internal peer port. Each node needs a stable internal URL in `KURA_NODE_URL`, and the other nodes need a way to discover or seed that URL through `KURA_PEERS` or `KURA_DISCOVERY_DNS_NAME`.

In Kubernetes, use a `StatefulSet` with one persistent volume per pod and a headless service for peer discovery. The headless service gives each pod a stable DNS name, and Kura uses those names to exchange membership, bootstrap state, and replicated artifacts over the internal peer port.

Outside Kubernetes, give each node a stable DNS name or IP address and set `KURA_PEERS` to the internal URLs of the nodes that should form the mesh. Every peer must be able to reach the internal endpoints used for status checks, bootstrap, and artifact replication.

Secure the peer plane with mTLS when nodes communicate over any shared or untrusted network. Configure `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH`, and `KURA_INTERNAL_TLS_KEY_PATH` together, make `KURA_NODE_URL` and every `KURA_PEERS` entry use `https://` on `KURA_INTERNAL_PORT`, and issue certificates whose SANs cover the DNS names peers use to call each other. With mTLS enabled, Kura serves `/_internal/*` through a listener that requires a client certificate signed by the configured CA.

Use network-level restrictions in addition to mTLS. In Kubernetes, allow the internal peer port only between pods that belong to the same cache deployment, for example with a `NetworkPolicy`. Outside Kubernetes, use firewall rules or security groups so the peer port is reachable only by other cache nodes. Public cache traffic should enter through the public HTTP or gRPC endpoints, not through the internal peer port.

## Deploy on Kubernetes {#deploy-on-kubernetes}

Kura is distributed as a Helm chart through GitHub Container Registry. It deploys Kura as a `StatefulSet` with persistent volumes, a headless service for peer discovery, and a regular service for HTTP and gRPC traffic.

```bash
helm upgrade --install kura oci://ghcr.io/tuist/charts/kura \
  --namespace kura \
  --create-namespace \
  --version <version> \
  --set image.tag=<tag> \
  --set config.region=local
```

For a self-hosted Tuist server running in the same cluster, expose the Kura service through the Tuist chart:

```yaml
server:
  kuraEndpointUrls:
    - http://kura.kura.svc.cluster.local:4000
```

This renders `TUIST_KURA_ENDPOINTS` in the server pod. When clients request the Kura cache technology, the server returns those endpoints.

> [!IMPORTANT]
> Every Kura node must own its own `KURA_DATA_DIR`. Kura takes an application-level writer lock on the data directory and expects exactly one process to own it. In Kubernetes, use one persistent volume per pod. Outside Kubernetes, do not point multiple processes at the same mounted directory.

## Deploy without Kubernetes {#deploy-without-kubernetes}

Kura can also run as a regular container on VMs or bare-metal hosts. In this mode, you are responsible for process supervision, persistent storage, routing, and peer discovery.

At minimum, each node needs a persistent data directory, a temporary directory, a public HTTP port, an internal peer URL, and either a static peer list or a discovery mechanism:

```bash
docker run -d --name kura \
  -p 4000:4000 \
  -p 50051:50051 \
  -p 7443:7443 \
  -v /var/lib/kura:/var/cache/kura \
  -e KURA_PORT=4000 \
  -e KURA_GRPC_PORT=50051 \
  -e KURA_INTERNAL_PORT=7443 \
  -e KURA_TENANT_ID=default \
  -e KURA_REGION=local \
  -e KURA_TMP_DIR=/tmp/kura \
  -e KURA_DATA_DIR=/var/cache/kura \
  -e KURA_NODE_URL=http://kura-1.internal:7443 \
  -e KURA_PEERS=http://kura-1.internal:7443,http://kura-2.internal:7443 \
  ghcr.io/tuist/kura:<tag>
```

Then configure the Tuist server with the URLs that clients can reach:

```bash
TUIST_KURA_ENDPOINTS=https://kura-1.example.com,https://kura-2.example.com
```

## Configuration {#configuration}

The Helm chart renders the common runtime settings from `values.yaml`. If you run Kura without Kubernetes, set the same variables directly on the process. Variables that the chart does not map directly can be injected through `extraEnv` or `extraEnvFrom`.

| Environment variable | Description | Required | Default | Helm value |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | Public HTTP port for cache traffic and health endpoints. | Yes | No default | `service.httpPort` |
| `KURA_GRPC_PORT` | gRPC port for Bazel and Buck2 REAPI traffic. | Yes | No default | `service.grpcPort` |
| `KURA_INTERNAL_PORT` | Internal HTTP or mTLS port used by Kura peers. | Yes | No default | `peerTls.internalPort` |
| `KURA_TENANT_ID` | Default tenant identifier for the node. | Yes | No default | `config.tenantId` |
| `KURA_REGION` | Region label used in metrics and replication state. | Yes | No default | `config.region` |
| `KURA_TMP_DIR` | Temporary directory for staged request bodies and multipart assembly. | Yes | No default | Fixed to `/tmp/kura` |
| `KURA_DATA_DIR` | Persistent directory for metadata state and segment files. | Yes | No default | Fixed to `/var/cache/kura` |
| `KURA_NODE_URL` | Canonical internal URL other peers use to reach this node. | Yes | No default | Derived from the pod DNS name and `peerTls.internalPort` |
| `KURA_PEERS` | Seed peer list used before discovery converges. | No | `KURA_NODE_URL` | Derived from the StatefulSet replicas |
| `KURA_DISCOVERY_DNS_NAME` | DNS name used for automatic peer discovery. | No | Disabled | Enabled by `config.discovery.enabled` |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | CA certificate used to verify peer mTLS. | No | Disabled | `peerTls.enabled` and `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | Certificate used by the internal peer mTLS listener. | No | Disabled | `peerTls.enabled` and `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | Private key used by the internal peer mTLS listener. | No | Disabled | `peerTls.enabled` and `peerTls.keyFileName` |
| `KURA_GRPC_TLS_CERT_PATH` | Certificate used to terminate TLS on the public gRPC listener. | No | Disabled | `extraEnv` |
| `KURA_GRPC_TLS_KEY_PATH` | Private key paired with `KURA_GRPC_TLS_CERT_PATH`. | No | Disabled | `extraEnv` |
| `KURA_FILE_DESCRIPTOR_POOL_SIZE` | File-descriptor budget for request and background I/O. | No | Auto-derived | `config.fileDescriptors.poolSize` |
| `KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS` | How long a request waits before FD backpressure fails the checkout. | No | `5000` | `config.fileDescriptors.acquireTimeoutMs` |
| `KURA_SEGMENT_HANDLE_CACHE_SIZE` | Maximum number of pinned segment read handles. | No | Auto-derived | `config.fileDescriptors.segmentHandleCacheSize` |
| `KURA_DRAIN_COMPLETION_TIMEOUT_MS` | Grace window for in-flight HTTP and gRPC work during shutdown. | No | `240000` | `config.shutdown.drainCompletionTimeoutMs` |
| `KURA_MEMORY_SOFT_LIMIT_BYTES` | Soft memory watermark where Kura starts reducing optional memory use. | No | Auto-derived | `config.memory.softLimitBytes` |
| `KURA_MEMORY_HARD_LIMIT_BYTES` | Hard memory watermark where Kura pauses replication and trims hot caches. | No | Auto-derived | `config.memory.hardLimitBytes` |
| `KURA_MANIFEST_CACHE_MAX_BYTES` | Maximum size of the in-memory manifest cache. | No | Auto-derived | `config.memory.manifestCacheMaxBytes` |
| `KURA_MAX_KEYVALUE_BYTES` | Maximum per-request keyvalue payload size. | No | `1048576` | `config.memory.maxKeyvalueBytes` |
| `KURA_METADATA_STORE_MAX_OPEN_FILES` | File descriptor budget reserved for the metadata store. | No | Auto-derived | `config.metadataStore.maxOpenFiles` |
| `KURA_METADATA_STORE_MAX_BACKGROUND_JOBS` | Background flush and compaction concurrency for the metadata store. | No | Auto-derived | `config.metadataStore.maxBackgroundJobs` |
| `KURA_METADATA_STORE_READ_CACHE_BYTES` | Capacity of the metadata-store read cache. | No | Auto-derived | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES` | Total memory budget reserved for metadata write buffering. | No | Auto-derived | `extraEnv` |
| `KURA_METADATA_STORE_WRITE_BUFFER_BYTES` | Size of each metadata write buffer before flush. | No | Auto-derived | `extraEnv` |
| `KURA_METADATA_STORE_MAX_WRITE_BUFFERS` | Maximum number of metadata write buffers kept in memory. | No | Auto-derived | `extraEnv` |
| `KURA_OUTBOX_MAX_DEPTH` | Maximum replication outbox depth before public writes return backpressure. | No | `100000` | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | How long an in-progress multipart upload may sit before expiring. | No | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | How often Kura scans for stale multipart uploads. | No | `600000` | `extraEnv` |
| `KURA_BOOTSTRAP_TIMEOUT_MS` | Maximum time a single bootstrap-from-peer task may run. | No | `1800000` | `extraEnv` |
| `KURA_BOOTSTRAP_MAX_CONCURRENT_PEERS` | Maximum concurrent bootstrap-from-peer tasks. | No | `8` | `extraEnv` |
| `KURA_TOKIO_WORKER_THREADS` | Number of Tokio worker threads. | No | Auto-derived | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP traces endpoint. Leave empty to disable tracing. | No | Disabled | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry service name. | Yes | No default | Pod name in Helm |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry deployment environment. | Yes | No default | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Sentry DSN for panic and error reporting. | No | Disabled | `extraEnv` or `extraEnvFrom` |
| `KURA_GEOIP_REFRESH_INTERVAL_SECS` | Interval for refreshing the vendored GeoIP database. Set `0` to disable refreshes. | No | `86400` | `config.geoip.refreshIntervalSecs` |
| `KURA_EXTENSION_ENABLED` | Enables Lua extension hooks. | No | Disabled | `extension.enabled` |
| `KURA_EXTENSION_SCRIPT_PATH` | Path to the Lua extension script. | Required when extensions are enabled | No default | Derived from `extension.mountDir` and `extension.scriptFileName` |
| `KURA_EXTENSION_HOOK_TIMEOUT_MS` | Timeout for each extension hook invocation. | No | `25` | `extraEnv` |
| `KURA_EXTENSION_AUTH_CACHE_ALLOW_TTL_SECONDS` | TTL for positive extension authentication and authorization cache entries. | No | `600` | `extraEnv` |
| `KURA_EXTENSION_AUTH_CACHE_DENY_TTL_SECONDS` | TTL for negative extension authentication and authorization cache entries. | No | `3` | `extraEnv` |
| `KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE` | Whether authentication hook errors reject the request. | No | `true` | `extraEnv` |
| `KURA_EXTENSION_FAIL_CLOSED_AUTHORIZE` | Whether authorization hook errors reject the request. | No | `true` | `extraEnv` |
| `KURA_EXTENSION_FAIL_OPEN_RESPONSE_HEADERS` | Whether response-header hook errors are ignored. | No | `true` | `extraEnv` |
| `KURA_EXTENSION_CACHE_MAX_ENTRIES` | Maximum entries kept in each extension cache. | No | `100000` | `extraEnv` |

If you enable internal peer mTLS, set `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH`, and `KURA_INTERNAL_TLS_KEY_PATH` together. `KURA_NODE_URL` and every value in `KURA_PEERS` must then use `https://` with the internal peer port.
