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

A self-hosted Tuist server takes those endpoints from static configuration. On the Tuist-hosted server, nodes authenticate with a credential and register themselves. Deploy a node first with one of the two sections below, then see [Connect nodes to Tuist](#connect-nodes-to-tuist).

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

For a self-hosted Tuist server running in the same cluster, tell the server which cache endpoints to hand to clients:

```yaml
server:
  cacheEndpointUrl: "http://kura.kura.svc.cluster.local:4000"
```

This renders `TUIST_CACHE_ENDPOINTS` in the server pod. On a self-hosted server the CLI is routed to whatever `TUIST_CACHE_ENDPOINTS` lists, so point it at your Kura service. For multiple nodes, use a comma-separated list.

> [!IMPORTANT]
> Every Kura node must own its own `KURA_DATA_DIR`. Kura takes an application-level writer lock on the data directory and expects exactly one process to own it. In Kubernetes, use one persistent volume per pod. Outside Kubernetes, do not point multiple processes at the same mounted directory.

## Deploy without Kubernetes {#deploy-without-kubernetes}

Kura can also run as a regular container on VMs or bare-metal hosts. In this mode, you are responsible for process supervision, persistent storage, routing, and peer discovery.

At minimum, each node needs a persistent data directory, a temporary directory, a public cache port (one listener serves both the HTTP cache API and REAPI gRPC), an internal peer URL, and either a static peer list or a discovery mechanism:

```bash
docker run -d --name kura \
  -p 4000:4000 \
  -p 7443:7443 \
  -v /var/lib/kura:/var/cache/kura \
  -e KURA_PORT=4000 \
  -e KURA_INTERNAL_PORT=7443 \
  -e KURA_TENANT_ID=default \
  -e KURA_REGION=local \
  -e KURA_TMP_DIR=/var/cache/kura/tmp \
  -e KURA_DATA_DIR=/var/cache/kura \
  -e KURA_NODE_URL=http://kura-1.internal:7443 \
  -e KURA_PEERS=http://kura-1.internal:7443,http://kura-2.internal:7443 \
  ghcr.io/tuist/kura:<tag>
```

Then configure the Tuist server with the URLs that clients can reach:

```bash
TUIST_CACHE_ENDPOINTS=https://kura-1.example.com,https://kura-2.example.com
```

## Connect nodes to Tuist {#connect-nodes-to-tuist}

Running a node is only half of the setup. Tuist also has to know the node exists before it can hand the endpoint to clients. How that happens depends on which Tuist server you use.

On a **self-hosted Tuist server**, you declare endpoints statically with `TUIST_CACHE_ENDPOINTS`, as shown in the deployment sections above. The server hands clients exactly what you list.

On the **Tuist-hosted server**, endpoints are not configured by hand. Each node authenticates with a credential you generate, then registers itself and reports its own liveness. This section covers that flow.

> [!IMPORTANT]
> **Enterprise plan**
>
> Self-hosted cache nodes are available on the Enterprise plan. The **Self-hosted servers** section described below only appears for accounts on that plan.

### Generate a node credential {#generate-a-node-credential}

In the Tuist dashboard, open your account, go to **Cache**, and find **Self-hosted servers**. Choose **Generate credential** to mint a client ID and secret.

The credential only authorizes traffic for the account that created it.

The secret is displayed once and is not recoverable after you close the dialog, so copy it straight into the secret store your nodes read from. Revoking a credential immediately stops every node using it from authenticating, so generate a replacement before revoking one that is in service.

### Enroll the node on boot {#enroll-the-node-on-boot}

Enrollment is the recommended way to bring a node up. Set `KURA_ENROLL_ON_BOOT` and give the node its credential and its own peer URL:

```bash
KURA_ENROLL_ON_BOOT=true
KURA_CONTROL_PLANE_URL=https://tuist.dev
KURA_CONTROL_PLANE_CLIENT_ID=<client ID>
KURA_CONTROL_PLANE_CLIENT_SECRET=<client secret>
KURA_NODE_URL=https://kura-1.internal:7443
```

The node generates its keypair locally, so the private key never leaves it, and receives a signed peer certificate, the account CA, its tenant identifier, and the peer list. That is everything you would otherwise configure by hand: an enrolled node needs no `KURA_TENANT_ID`, no `KURA_PEERS`, and no peer TLS setup.

Leave `KURA_INTERNAL_TLS_*` unset: enrollment writes the certificate material to a `tls` directory under `KURA_DATA_DIR`. Set those paths yourself only when you supply the certificates instead of enrolling, as described in [Build a cache mesh](#build-a-cache-mesh).

A node joining an account's mesh for the first time pulls the account's existing cache before it becomes a serving member of the ring. Size the data volume for the whole cache, and expect the first join to take a while over a wide-area link. The node reports `joining` until it has caught up, then `serving`.

### Advertise the endpoint {#advertise-the-endpoint}

Enrollment joins the mesh. Advertising is what makes clients route to the node. Add the registration variables:

```bash
KURA_REGISTRATION_URL=https://tuist.dev/_internal/kura/mesh/registrations
KURA_ADVERTISED_HTTP_URL=https://kura-1.example.com:4443
```

The node heartbeats every 60 seconds against a 180-second lease, and drops out of rotation on its own if it stops. Tuist never calls the node, so it only has to be reachable by your clients, not from the internet.

### Verify the node is serving {#verify-the-node-is-serving}

Back in **Cache** in the dashboard, the node appears under **Registered nodes** with its endpoint, region, status, and last heartbeat. A node that never appears is not reaching the registration endpoint or is failing authorization. A node that appears and then disappears has stopped heartbeating or has stopped reporting itself ready.

### Match the tenant identifier to your account handle {#match-the-tenant-identifier}

`KURA_TENANT_ID` must equal your Tuist account handle. The control plane compares the heartbeat's tenant against the account resolved from the credential and rejects a mismatch with `409 tenant_mismatch`, so a node with the wrong value authenticates successfully and still never registers.

> [!IMPORTANT]
> Both the Helm chart and the container example earlier in this guide default this to `default`. That value is correct for a self-hosted Tuist server, where the tenant is a local label, and wrong for an account on the Tuist-hosted server, where it has to name the account. Enrolling the node avoids the question entirely, because the control plane supplies the value.

An unset `KURA_TENANT_ID` does not skip the check. It disables registration altogether: the node keeps serving cache traffic, nothing appears in the dashboard, and no error is reported. If a node is healthy but missing from **Registered nodes**, check this variable first.

### Choose an advertised URL your clients can reach {#choose-an-advertised-url}

The advertised URL is handed to every client on the account, not only the ones near the node. Developer machines resolve it the same way runners do.

An internal-only hostname is therefore only appropriate when every client that will receive it can resolve and reach that name. If your nodes sit on a network your developers are not always on, either keep the advertisement to environments that can reach it, publish a name that resolves from everywhere clients build, or run a node near each population and let the mesh replicate between them.

## Build a cache mesh {#build-a-cache-mesh}

A cache mesh lets you place cache capacity next to the compute that needs it. A company might run one node near its main CI runners, another close to developers in Europe, and another near a US office or regional build cluster. Each location reads and writes against the closest node, while Kura replicates artifacts and metadata in the background so later builds in other locations can reuse the same outputs.

The mesh only works if nodes can reach each other on Kura's internal peer port. That peer plane is separate from the public cache endpoints that Tuist clients use. Kura uses it to check membership, backfill newly joined nodes, and replicate artifacts after local writes are accepted.

We strongly recommend securing the peer plane with [mTLS](https://en.wikipedia.org/wiki/Mutual_authentication) when nodes communicate across regions, clouds, VPCs, offices, or any network that is not fully private to the cache deployment. With mTLS enabled, Kura only serves internal replication endpoints to peers presenting a certificate signed by the configured CA. The peer certificates must cover the DNS names nodes use to call each other, and peer URLs must use `https://` on the internal port.

> [!NOTE]
> Nodes that enroll against a Tuist-hosted control plane receive their peer certificate and the account CA during enrollment, so the manual steps below apply to meshes that do not enroll.

For example, this generates a private CA and one peer certificate that can be mounted by every node in a small mesh. Replace the DNS names with the internal names your nodes use in `KURA_NODE_URL` and `KURA_PEERS`.

```bash
mkdir -p kura-peer-tls
cd kura-peer-tls

openssl ecparam -genkey -name prime256v1 -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 \
  -subj "/CN=kura-peer-ca" \
  -out ca.pem

openssl ecparam -genkey -name prime256v1 -noout -out tls.key
openssl req -new -key tls.key \
  -subj "/CN=kura-peer" \
  -out peer.csr

cat > peer.ext <<'EOF'
subjectAltName = DNS:kura-0.kura-headless.kura.svc.cluster.local,DNS:kura-1.kura-headless.kura.svc.cluster.local,DNS:kura-2.kura-headless.kura.svc.cluster.local,DNS:kura-1.internal,DNS:kura-2.internal
extendedKeyUsage = serverAuth,clientAuth
keyUsage = digitalSignature,keyEncipherment
EOF

openssl x509 -req -in peer.csr \
  -CA ca.pem \
  -CAkey ca.key \
  -CAcreateserial \
  -out tls.crt \
  -days 730 \
  -sha256 \
  -extfile peer.ext
```

### Catch-up between nodes {#catch-up-between-nodes}

A node that joins or rejoins a mesh **backfills**: it walks each peer's entries newest-first and pulls what it is missing, while live replication covers writes made while the peer is in view. A backfill pass reaches back from the peer's newest entry to the older of the node's segment-ring horizon and its last completed pass, so a node is guaranteed to hold the recent data, not necessarily all of it. `KURA_BACKFILL_MARGIN_PERCENT` sets how far back the horizon sits.

Two consequences are worth knowing before you run a mesh:

- A node reports `/ready` once its segment ring is `KURA_BACKFILL_READY_RING_PERCENT` full **or** its first backfill cycle settles, and readiness then holds for the rest of the process lifetime. A later peer flap never takes a serving node out of rotation.
- A cycle also settles when a peer is unreachable for long enough. A node whose only peer is down therefore becomes Ready while holding little or no data. It serves misses rather than errors. `/status/rollout` reports `backfill_initial_cycle` (`pending`, `complete` or `degraded`) if you want to gate a rollout on the difference.

**Upgrading a mesh across the backfill change.** Kura releases before backfill catch up through a different, now-removed peer protocol. Roll every node onto a release that runs backfill **before** you take a release that only speaks backfill. Nodes on the two protocols cannot catch up from each other: a warm node keeps serving from its volume but stops closing its gap, and a node that starts on an empty volume in that window never becomes Ready. The chart sets `KURA_BACKFILL_ENABLED=true` for you, so a chart-first upgrade covers this. A single `helm upgrade` that moves the chart and the image together does not.

Use network-level restrictions in addition to mTLS. In Kubernetes, run Kura as a `StatefulSet` with one persistent volume per pod and a headless service for peer discovery, then allow the internal peer port only between pods that belong to the same cache deployment, for example with a `NetworkPolicy`. Outside Kubernetes, give each node a stable DNS name or IP address, seed the mesh with the internal URLs of the other nodes, and use firewall rules or security groups so only cache nodes can reach the peer port. Public cache traffic should enter through the public HTTP or gRPC endpoints, not through the internal peer plane.

## Configuration {#configuration}

The Helm chart renders the common runtime settings from `values.yaml`. If you run Kura without Kubernetes, set the same variables directly on the process. Variables that the chart does not map directly can be injected through `extraEnv` or `extraEnvFrom`.

| Environment variable | Description | Required | Default | Helm value |
| --- | --- | --- | --- | --- |
| `KURA_PORT` | Public cache port. One listener serves the HTTP cache API, health endpoints, and Bazel/Buck2 REAPI gRPC (h2c). | Yes | No default | `service.httpPort` |
| `KURA_INTERNAL_PORT` | Internal HTTP or mTLS port used by Kura peers. | Yes | No default | `peerTls.internalPort` |
| `KURA_TENANT_ID` | Default tenant identifier for the node. | Yes | No default | `config.tenantId` |
| `KURA_REGION` | Region label used in metrics and replication state. | Yes | No default | `config.region` |
| `KURA_TMP_DIR` | Temporary directory for staged request bodies and multipart assembly. | Yes | No default | Fixed to `/var/cache/kura/tmp` |
| `KURA_TMP_DIR_MAX_BYTES` | Maximum staged bytes admitted into `KURA_TMP_DIR` before requests receive backpressure. | No | `8589934592` | `config.tmpDirMaxBytes` |
| `KURA_DATA_DIR` | Persistent directory for metadata state and segment files. | Yes | No default | Fixed to `/var/cache/kura` |
| `KURA_NODE_URL` | Canonical internal URL other peers use to reach this node. | Yes | No default | Derived from the pod DNS name and `peerTls.internalPort` |
| `KURA_PEERS` | Seed peer list used before discovery converges. | No | `KURA_NODE_URL` | Derived from the StatefulSet replicas |
| `KURA_DISCOVERY_DNS_NAME` | DNS name used for automatic peer discovery. | No | Disabled | Enabled by `config.discovery.enabled` |
| `KURA_INTERNAL_TLS_CA_CERT_PATH` | CA certificate used to verify peer mTLS. | No | Disabled, or derived under `KURA_DATA_DIR` when the node enrolls | `peerTls.enabled` and `peerTls.caCertFileName` |
| `KURA_INTERNAL_TLS_CERT_PATH` | Certificate used by the internal peer mTLS listener. | No | Disabled, or derived under `KURA_DATA_DIR` when the node enrolls | `peerTls.enabled` and `peerTls.certFileName` |
| `KURA_INTERNAL_TLS_KEY_PATH` | Private key used by the internal peer mTLS listener. | No | Disabled, or derived under `KURA_DATA_DIR` when the node enrolls | `peerTls.enabled` and `peerTls.keyFileName` |
| `KURA_PUBLIC_TLS_CERT_PATH` | Certificate used to terminate TLS on the co-hosted HTTPS listener (`KURA_HTTPS_PORT`). | No | Disabled | `extraEnv` |
| `KURA_PUBLIC_TLS_KEY_PATH` | Private key paired with `KURA_PUBLIC_TLS_CERT_PATH`. | No | Disabled | `extraEnv` |
| `KURA_HTTPS_PORT` | TLS port serving the same co-hosted HTTP + gRPC surface (ALPN-negotiated). Only bound when the public TLS paths are set. | No | `4443` | `extraEnv` |
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
| `KURA_OUTBOX_MAX_DEPTH_PER_PEER` | Replication outbox messages one peer may hold. A cache write is refused with retryable backpressure once any of its replication peers is at this depth, or once the node is at its total of this times the peer count (at least one share, at most 1,000,000), which follows the mesh as nodes join and leave. A node with no peers enqueues nothing. | No | `100000` | `extraEnv` |
| `KURA_OUTBOX_MAX_DEPTH` | A fixed node-wide outbox total that replaces the per-peer share when set. | No | Unset | `extraEnv` |
| `KURA_MULTIPART_UPLOAD_TTL_MS` | How long an in-progress multipart upload may sit before expiring. | No | `86400000` | `extraEnv` |
| `KURA_MULTIPART_JANITOR_INTERVAL_MS` | How often Kura scans for stale multipart uploads. | No | `600000` | `extraEnv` |
| `KURA_BACKFILL_MARGIN_PERCENT` | Share of the age-ordered segment ring, counted from the newest, that bounds how far back a backfill pass reaches. | No | `40` | `config.backfill.marginPercent` |
| `KURA_BACKFILL_READY_RING_PERCENT` | Segment-ring fullness at which a node still running its first backfill cycle reports itself ready. | No | Half of `KURA_BACKFILL_MARGIN_PERCENT` | `config.backfill.readyRingPercent` |
| `KURA_BACKFILL_BATCH_BYTES` | Byte threshold one backfill bodies batch is composed against, and the size above which an entry is fetched on its own. | No | `33554432` | `config.backfill.batchBytes` |
| `KURA_TOKIO_WORKER_THREADS` | Number of Tokio worker threads. | No | Auto-derived | `extraEnv` |
| `KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | OTLP traces endpoint. Leave empty to disable tracing. | No | Disabled | `config.telemetry.otlpTracesEndpoint` |
| `KURA_OTEL_SERVICE_NAME` | OpenTelemetry service name. | Yes | No default | Pod name in Helm |
| `KURA_OTEL_DEPLOYMENT_ENVIRONMENT` | OpenTelemetry deployment environment. | Yes | No default | `config.telemetry.deploymentEnvironment` |
| `KURA_SENTRY_DSN` | Sentry DSN for panic and error reporting. | No | Disabled | `extraEnv` or `extraEnvFrom` |
| `KURA_NODE_COUNTRY` | ISO 3166-1 alpha-2 country of the datacenter the node runs in, stamped on exported traces as `geo.country.iso_code`. | No | Derived from `KURA_REGION` when its prefix is a country code | `extraEnv` |
| `KURA_NODE_SUBDIVISION` | ISO 3166-2 subdivision of that datacenter (e.g. `US-CA`), stamped as `geo.region.iso_code`. | No | Unset | `extraEnv` |
| `KURA_AUTH_ENABLED` | Requires callers to present a valid Tuist token. Setting `KURA_AUTH_TUIST_URL` enables authorization on its own, and setting this to `false` does not turn it back off — unset the URL to run a node without authorization. | No | Disabled | `auth.enabled` |
| `KURA_AUTH_TUIST_URL` | Tuist server the node authorizes against. Enables authorization on its own. | Required when authorization is enabled | No default | `auth.tuistUrl` |
| `KURA_AUTH_TUIST_CONNECT_TIMEOUT_MS` | Connect timeout for calls to that server. | No | `500` | `extraEnv` |
| `KURA_AUTH_TUIST_REQUEST_TIMEOUT_MS` | Request timeout for calls to that server. | No | `1500` | `extraEnv` |
| `KURA_AUTH_JWT_SECRET` | Shared secret for tokens the node can read itself, skipping a round trip. It signs as well as it verifies, so only use it where the node and the server are the same trust boundary. Self-hosted nodes normally leave this unset. | No | Disabled | `extraEnv` or `extraEnvFrom` |
| `KURA_AUTH_JWT_PUBLIC_KEY` | Public half of the keypair the server signs cache tokens with, as one or more concatenated PEM blocks. Reads those tokens without being able to mint one, which is what a node reachable from the internet should hold. Mutually exclusive with `KURA_AUTH_JWT_SECRET`. | No | Disabled | `extraEnvFrom` |
| `KURA_AUTH_JWT_ALGORITHM` | Algorithm for that key: `HS256`, `HS384` or `HS512` with a secret, `ES256` with a public key. | No | `HS256` with a secret, `ES256` with a public key | `extraEnv` |
| `KURA_AUTH_JWT_ISSUER` | Issuer that tokens must carry. | No | Unchecked | `extraEnv` |
| `KURA_AUTH_JWT_AUDIENCES` | Comma-separated audiences that tokens must carry. | No | Unchecked | `extraEnv` |
| `KURA_AUTH_CACHE_MAX_ENTRIES` | Maximum entries kept in each of the authentication and authorization caches. | No | `100000` | `extraEnv` |
| `KURA_ENROLL_ON_BOOT` | Enrolls the node with the control plane on every boot, provisioning its peer certificate and supplying `KURA_TENANT_ID` and `KURA_PEERS`. | No | Disabled | `extraEnv` |
| `KURA_CONTROL_PLANE_URL` | Tuist server the node enrolls against. | Required when enrolling | No default | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_ID` | Client ID of the node credential generated in the dashboard. | Required when enrolling or registering | No default | `extraEnv` |
| `KURA_CONTROL_PLANE_CLIENT_SECRET` | Client secret paired with `KURA_CONTROL_PLANE_CLIENT_ID`. | Required when enrolling or registering | No default | `extraEnv` |
| `KURA_REGISTRATION_URL` | Absolute URL the node posts registration heartbeats to, advertising its client-facing endpoint. | Required when registering | No default | `extraEnv` |
| `KURA_ADVERTISED_HTTP_URL` | Client-facing cache URL the control plane hands to clients. Must be reachable by every client on the account. | Required when registering | No default | `extraEnv` |
| `KURA_REGISTRATION_INTERVAL_MS` | Registration heartbeat cadence. The lease is several missed heartbeats wide, so a single dropped heartbeat does not drop the endpoint. | No | `60000` | `extraEnv` |

If you enable internal peer mTLS, set `KURA_INTERNAL_TLS_CA_CERT_PATH`, `KURA_INTERNAL_TLS_CERT_PATH`, and `KURA_INTERNAL_TLS_KEY_PATH` together. `KURA_NODE_URL` and every value in `KURA_PEERS` must then use `https://` with the internal peer port.
