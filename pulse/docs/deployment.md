# Deploying Pulse

Pulse runs as a stateless container in front of an S3-compatible bucket. The
bucket holds every acknowledged record; the container keeps nothing on disk
that cannot be thrown away. Each release publishes a container image and a
Helm chart with the same version:

- Image: `ghcr.io/tuist/pulse:<version>`
- Chart: `oci://ghcr.io/tuist/charts/pulse`, version `<version>`

Pick a version from the [releases page](https://github.com/tuist/tuist/releases).

## Monorepo migration

Pulse development now lives in the Tuist monorepo. Releases use
`pulse@<version>` tags, the `ghcr.io/tuist/pulse` image and the
`oci://ghcr.io/tuist/charts/pulse` chart. Build from the `pulse/` directory when
working from source; precompiled NIF artifacts are attached to the monorepo's
Pulse releases, not the archived repository's releases.

This is a complete namespace rename, not a rolling-compatible upgrade. Runtime
variables use `PULSE_*`, the OTP application is `:pulse`, modules are `Pulse.*`
and `PulseWeb.*`, and monitoring metrics use `pulse_*`. Helm values retain their
shape, but the chart supplies the renamed variables. The development Compose
stack defaults to a `pulse` bucket.

Credential issuers must mint `pulse_ik_` ingest keys with `pulse-ik+jwt` headers
and re-sign status lists with `pulse-status+jwt`. Old signed credentials are not
accepted. Parquet metadata uses `pulse.metric.postings.v1`, `PULSEMP1`,
`pulse.metric.rollup`, `pulse.log.rollup` and `pulse.log.rollup.sources`.
Readers also recognize the corresponding historical metadata names and postings
magic. Existing buckets, object keys, manifests and historical rollups can be
reused without rewriting stored objects. New rollups use only Pulse metadata.
Historical identity strings remain narrowly scoped to compatibility readers and
deterministic keyed-publication hashes so retries do not duplicate acknowledged
data. They are not runtime configuration aliases.

Do not run both Helm releases as independent maintenance fleets over the same
bucket during the rename. Stop the old workload before starting Pulse, and
check chart-generated resource names, Secret references, service discovery and
collector destinations. This source migration does not change an existing
deployment automatically.

Quiesce ingestion, drain accepted work and pending recording publications, and
stop every old reader, writer and compactor before the cutover. Preserve existing
credential bytes and tenant prefixes; change endpoint audiences and consumers
together. Shared-secret deployments do not require reissuing hosted signed
credentials. Previously issued alert pagination cursors must restart.

After Pulse publishes new metric or log rollups, the unmodified old binary is
not a safe rollback target: it cannot read the new metadata. Recover using a
compatibility-capable Pulse release, not an old container or a manifest backup
that could omit subsequent acknowledgments. Do not change retention enforcement
as part of this migration.

> [!IMPORTANT]
> Run one Pulse node per bucket for now. Multi-node clustering is not wired into
> the release yet. Rolling updates briefly run two nodes; conditional writes in
> object storage keep that safe, but do not scale out permanently.

## Before you start

Periodic [reliability assessments](reliability.md) are optional and disabled by
default. Set the chart's `reliability.enabled`, explicit `tenants` and
`priceValidUntil`, and provide `PULSE_RELIABILITY_OPENAI_API_KEY` via Secret-backed
`extraEnv`. Review per-tenant allowances before enabling paid dispatch. A separate
`reliability.investigationUrl` plus Secret-backed
`PULSE_RELIABILITY_INVESTIGATION_TOKEN` enables a fixed HTTPS external receiver;
it must enforce the [grant and completion contract](reliability.md#external-investigations).
Expose `POST /api/v1/reliability/investigations/:id/complete` only as needed for
that receiver; each callback requires its run-specific bearer token. Provision
read-only tenant MCP credentials separately. Raw storage/retention is unchanged.

You need:

- A Kubernetes cluster with Helm 3.8 or later, or any host that runs containers.
- A dedicated bucket on storage that supports conditional writes, plus an access
  key that can list, read, write, and delete objects in it. See
  [object storage](configuration.md#object-storage).
- One bearer token per tenant. See [tenants and tokens](configuration.md#tenants-and-tokens).

## Install with Helm

Create a values file. Keep secrets out of version control, or use
[an existing Secret](#using-an-existing-secret) instead:

```yaml
# pulse-values.yaml
storage:
  bucket: pulse-telemetry
  region: us-east-1
  # endpoint: https://<account>.r2.cloudflarestorage.com
  accessKeyId: AKIA...
  secretAccessKey: ...

tenantTokens:
  production: "sha256$<digest of the production token>"
```

Install it:

```sh
helm install pulse oci://ghcr.io/tuist/charts/pulse \
  --version <version> \
  --namespace observability --create-namespace \
  --values pulse-values.yaml
```

The chart checks required values and digest formats while rendering, so a
mistake fails the install instead of producing a crash-looping pod. Check that the
node reached storage:

```sh
kubectl -n observability port-forward svc/pulse 4000:4000
curl -s localhost:4000/readyz
# {"status":"ok","checks":{"manifest":"ok","query_workers":"ok","storage":"ok"}}
```

[`infra/helm/pulse/values.yaml`](../../infra/helm/pulse/values.yaml) documents every value.
The ones you are most likely to change:

| Value | Purpose |
| --- | --- |
| `storage.*` | Bucket, region, endpoint, and credentials. |
| `tenantTokens` | Tenant name to token digest. Optional when `workloadIdentity.trust` or `issuer` is set. |
| `issuer` | Trusted credential issuer whose signed tokens carry tenant and scopes. Empty disables it. See [issuer credentials](issuer-credentials.md). |
| `workloadIdentity.trust` | Trusted Kubernetes ServiceAccount token issuers with inline or URL-fetched public keys and subject-to-tenant/capability bindings. See [workload identity](configuration.md#workload-identity). |
| `workloadIdentity.kubernetesApiToken.enabled` | Mount a projected Kubernetes API token and the cluster CA for [JWKS URL key sources](configuration.md#jwks-url-key-sources). Default `false`. |
| `existingSecret` | Use a Secret you manage instead of chart-rendered credentials. |
| `ingress.*` | Expose ingestion and queries outside the cluster. |
| `serviceMonitor.enabled` | Create a Prometheus Operator `ServiceMonitor` for self-monitoring. |
| `prometheusRule.enabled` | Create a Prometheus Operator `PrometheusRule` with the [self-monitoring alerts](self-monitoring.md#alerts). |
| `metricsFooterPruning.enabled` | Disabled by default. Footer-first exclusion for ordinary metric queries, not metadata discovery. Requires strong ETags, suffix Range and GET If-Match; matching sources can add GETs and hit budgets earlier. See [prerequisites and limits](metric-footer-pruning.md). |
| `metricsCompaction.enabled` | Merge small metrics segments. Read [the prerequisites](configuration.md#metrics-compaction) first. |
| `metricsCompaction.finalize` | With compaction, rewrite settled hours into metric-grouped segments and hourly rollups, and group the current hour's settled batches by metric (default `true`); see [long ranges](configuration.md#long-dashboard-and-alert-ranges). |
| `logCompaction.rollups` | With log compaction, per-minute line/byte counts per stream for volume panels (default `true`); see [log volume rollups](configuration.md#log-volume-rollups). |
| `logCompaction.groupByStream` | With log compaction, regroup settled log segments by service so stream selectors read only their own service's segments (default `true`); see [stream-grouped log segments](configuration.md#stream-grouped-log-segments). |
| `manifestBackups.enabled`, `manifestBackups.intervalMs` | Pulse-side manifest backups of compacted prefixes, every 15 minutes by default; cleanup waits for them. See [manifest backups](configuration.md#manifest-backups). |
| `retention.*` | Experimental event-time retention: `enabled`, `logsDays`, `metricsDays`, `tracesDays`, `mode` (`observe`, `enforce`, `paused`), grace, cadence, deletion limit, timeout, migration timeout, future skew and sweep horizon. Defaults keep data indefinitely. Read [retention](retention.md) first; enforcing is irreversible. |
| `tempoSearch.enabled` | Disabled by default. Experimental complete-retained-context Tempo search and five-scope discovery (parent-string-filtered names/values; names are complete hints, not matching-key proofs, 2M owner-plus-attribute work units per attempt before filtering, reducing dense flat-scope capacity); complete-context search can use publication-proven exact-service candidate pruning then conservative ID context recovery, never time clipping. Unknown/legacy sources read. Metadata/page/heap limits can bind before the hard 8192-ref catalog maximum; actual GETs retain cumulative 1024-input / 32 MiB / 1M-raw-row bounds. Probe fallback can exhaust limits late; unread irrelevant sources are not integrity-scrubbed. Requires metadata2/export3/search6/discovery12, tuple `{2,1,3,7,12}`, across every serving artifact; no representative posting/capacity/client acceptance. Bounded negated-regex/status/int64 OR/span-duration and unscoped span-first search expressions disable the service planner and add a 20M prefilter work ceiling per attempt; see [expression semantics](trace-query-expressions.md). Omitted HTTP search bounds or paired zeros scan all retained context under unchanged ceilings; partial search windows reject. Discovery retains its own all-source header/provider scan and does not use service/ID planning. Default names combine five namespaces plus v2 static suggestions under one global work/dictionary budget (20 intrinsic reservations also before v1 flattening); all errors fail whole. Unscoped values union three original owners after optional bounded same-parent resource/span string filters, a complete extension rather than Tempo's ignored-query fast path. Same-key equality and unsupported filters reject; matching complex targets/unknown legacy/corruption never become partial results. Query-aware unscoped and separately window-aware filtered-unscoped adapter support is required; old callbacks never receive new modes. Floats (including non-finite classes) and seven parent-filtered stored intrinsic strings plus event:timeSinceStart exact signed int nanoseconds use normal storage/work bounds. Event-time filters are a complete extension versus upstream's empty filtered path; no event invents no value, default time0 may yield negative offsets. Invalid requested event times fail even on nonmatches; explicit event-time and separate windowed-event-time support fence old callbacks (paired windows select whole retention-visible segment envelopes, not point-time filtering or indexed I/O; compaction can broaden suggestions, all source header/provider bounds still apply; require matching capability-12 artifacts on every serving instance). Root name/service dictionaries recover complete retained candidate context, not a matching child's fields. Missing/ambiguous roots or missing original string root service fail409 whole; in-flight and retention-straddling/multi-root traces can make broad/recent autocomplete unusable. No skip/default invention. All retained root S3 data must fit1024 objects/32MiB compressed/1M raw rows even for narrow windows; no service/ID planning, replay decodes all sources with header/body agreement. 65,536 candidates/16MiB bookkeeping and2M resource/span/link owner+attr work plus existing dictionary/result limits; dedicated root/window execution required. Not transparent autocomplete parity. Canonical trace:duration now measures full retained envelopes without requiring roots; it can grow on ingest/shrink on retention, not exporter duration. No filters emits int nanoseconds, supported filters emit Go duration strings (µs), both lexical; caches must separate those vocabularies. Same whole-tenant input/replay bounds,2M resource/span owner+attr work,65,536 groups/80B-per-summary charge within16MiB (not total native memory),5000/1MiB dictionary/result limits; broad high-cardinality queries commonly fail422. New duration/window adapters required; static empty duration/span:duration/traceDuration remain unchanged. Also enables authenticated/admitted static intrinsic vocabulary without storage reads; it is not stored-data evidence. Check cardinality, memory and provider limits before opting in; see [Tempo search](traces.md#experimental-tempo-search). |
| `traceCompaction.enabled` | Native trace merges, on by default; safe without bucket versioning while manifest backups are on. See [traces](traces.md#native-compaction). |
| `tempoSearch.contextHorizonMs` | How far around candidate segments Tempo search reads a trace's other spans (default one hour, `0` for all retained sources). See [traces](traces.md#search-context-horizon). |
| `tenantLimits` | Per-tenant admission limits (`default` and `tenants` entries), rendered as `PULSE_TENANT_LIMITS_JSON`. See [per-tenant limits](scaling.md#per-tenant-limits). |
| `tenantRegistry.*`, `admin.tokenHashes` | Runtime tenant lifecycle through the admin API, its cache TTL and deletion grace, and the admin token digests (stored in the chart secret as `PULSE_ADMIN_TOKENS`). See [tenants and usage](tenants.md). |
| `usage.enabled`, `usage.flushIntervalMs` | Per-tenant usage metering written to the bucket. See [usage metering](tenants.md#usage-metering). |
| `replicaCount`, `autoscaling.*` | Instances of the combined Deployment, or a CPU-based (or custom-metric) HorizontalPodAutoscaler. Any instance serves any tenant; see [scaling](scaling.md). |
| `pools.*` | Separate `ingest`, `query` and `maintenance` Deployments with their own replicas, resources and autoscaling. The ingress routes receiver paths to the ingest pool. See [separate pools](scaling.md#separate-pools). |
| `clustering.enabled` | Join pods into one Erlang cluster through a headless Service, so rendezvous ownership spreads background work. Generates `RELEASE_COOKIE` into the chart Secret (add it yourself with `existingSecret`). |
| `ingestLimits` | Per-request ingest budgets, keyed by setting name, such as `max_records`. |
| `ingestBatching.maxConcurrentRequests` | Node-local bound on concurrently processed ingest requests shared fairly between metrics, logs and traces; excess requests receive a retryable `429`. Empty (default) derives it from `resources.limits.memory`, see [node memory envelope](configuration.md#node-memory-envelope). |
| `ingestBatching.reservedRequestsPerSignal` | Slots each signal class keeps for itself; empty (default) means an eighth of `maxConcurrentRequests`, at least 1. See [ingest admission](configuration.md#ingest-admission). |
| `ingestBatching.maxPendingBytes` | Estimated memory of coalesced requests that release their slot while they wait for publication (default `67108864`); `0` disables the handoff. |
| `ingestBatching.flushIntervalMs` | Ingest coalescing and manifest publication window (`0..10000` ms); `0` disables it. Bounds object-store PUTs per signal and instance; read [the tradeoffs](configuration.md#ingest-coalescing) and [storage costs](storage-costs.md). |
| `mcp.allowedOrigins` | Browser origins allowed to call the Model Context Protocol endpoint. |
| `sentry.projects` | Experimental Sentry ingest-only project credentials and tenant/service bindings, with optional per-project `allowed_domains` (32 patterns maximum, 256 UTF-8 bytes each). Omission preserves unrestricted origins; `[]` denies Origin-bearing requests, not authenticated SDKs without Origin. Empty project map by default; add exact SDK ingress paths explicitly. See [error tracking](error-tracking.md). |
| `sentry.projectionEnabled` | Separately enable the experimental S3 issue index and bounded error-rate detector, default `false`; no effect on ingest acknowledgment. See [error monitoring](error-monitoring.md). |
| `sentry.historyDays` | Derived error-history horizon (`1..365` days), default `1`; independent of raw log retention. |
| `sentry.projectionIntervalMs` | One-project worker cadence (`1000..60000` ms), default `5000`; measure freshness and read cost before reducing it. |
| `alerting.principals` | Dedicated alert principal identities, hashed credentials and capabilities; see [alerting](alerting.md). |
| `alerting.evaluationEnabled` | Opt-in experimental native evaluation, default `false`. Grafana execution remains unsupported; native delivery has a separate opt-in. |
| `alerting.notificationsEnabled` | Opt-in native Slack delivery, default `false`; not Grafana routing/template parity. |
| `alerting.notificationTargets` | Public target descriptors; reference webhook environment secrets supplied through `extraEnv`, never inline URLs. |
| `alerting.sourceBindings` | Explicit tenant/original-UID/native-promql or native-logql mappings for read-only disabled graph previews, default `[]`; no URLs or implicit source residency. See [graph previews](alerting.md#preview-an-imported-expression-graph). |
| `alerting.pollIntervalMs` | Durable rule discovery interval (`1000..60000` ms), default `5000`; benchmark read cost before lowering it. |
| `resources` | CPU and memory. The defaults are starting points, not measured capacity. |

### Using an existing secret

To manage credentials with a secret store or an operator, create a Secret with
these keys and set `existingSecret` to its name:

```sh
kubectl -n observability create secret generic pulse-credentials \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  --from-literal=PULSE_TENANT_TOKENS='{"production":"sha256$<digest>"}' \
  --from-literal=PULSE_S3_ACCESS_KEY_ID=AKIA... \
  --from-literal=PULSE_S3_SECRET_ACCESS_KEY=...
```

The chart then ignores `secretKeyBase`, `tenantTokens`, `admin.tokenHashes` and
the storage credentials in values. To enable the [admin API](tenants.md#admin-api),
add an optional `PULSE_ADMIN_TOKENS` key holding a JSON array of
`sha256$<digest>` values. Pods do not restart automatically when an external Secret
changes; run `kubectl rollout restart deployment/pulse` after updating it.

### Workload identity

To let a Kubernetes workload, including one in another cluster, authenticate
with its projected ServiceAccount token, pin the issuing cluster's public keys
and bind the ServiceAccount to a tenant. The keys are public, so they can live
in values:

```yaml
workloadIdentity:
  trust:
    - name: atlas-production
      issuer: https://kubernetes.default.svc.cluster.local
      audiences: [pulse.tuist.dev]
      max_token_ttl_seconds: 3600
      keys:
        type: inline
        # Output of: kubectl --context <issuing-cluster> get --raw /openid/v1/jwks
        jwks: '{"keys":[{"use":"sig","kty":"RSA","kid":"<kid>","alg":"RS256","n":"<modulus>","e":"AQAB"}]}'
      bindings:
        - subject: system:serviceaccount:atlas-production:atlas
          tenant: tuist
          capabilities: [read]
```

`jwks` may also be a YAML object. In that case, quote the `"n"` key, because
YAML reads a bare `n` as `false`. The chart rejects keys without `"n"`. The
chart renders this as `PULSE_WORKLOAD_IDENTITY_JSON`. See
[workload identity](configuration.md#workload-identity) for the checks Pulse
applies and how to rotate keys.

For workloads in Pulse's own cluster, such as Grafana Alloy, let Pulse fetch
the keys from the API server so key rotation needs no values change:

```yaml
workloadIdentity:
  kubernetesApiToken:
    enabled: true   # mounts a projected API token and the cluster CA
  trust:
    - name: local-cluster
      issuer: https://kubernetes.default.svc.cluster.local
      audiences: [pulse.tuist.dev]
      keys:
        type: url
        url: https://kubernetes.default.svc/openid/v1/jwks
        ca_file: /var/run/secrets/pulse/kubernetes-api/ca.crt
        token_file: /var/run/secrets/pulse/kubernetes-api/token
      bindings:
        - subject: system:serviceaccount:monitoring:alloy
          tenant: tuist
          capabilities: [ingest]
```

See [JWKS URL key sources](configuration.md#jwks-url-key-sources) for refresh
and failure behavior.

## Networking and TLS

Pulse serves plain HTTP on port 4000 and expects TLS to terminate in front of
it, at an ingress controller, load balancer, or service mesh. In-cluster
collectors can talk to the Service directly. When the
[OTLP/gRPC receiver](otlp-grpc.md) is enabled (`otlpGrpc.enabled`), it listens
on its own port (4317 by default), also in plain text; expose it through a
gRPC-capable load balancer or ingress.

The same listener serves ingestion, queries, the Model Context Protocol, health
probes, and the unauthenticated self-monitoring endpoint `/metrics`. Never expose
the whole listener publicly. The chart's ingress routes only these paths:

| Path | Type | Serves |
| --- | --- | --- |
| `/v1/logs` | Exact | OpenTelemetry logs |
| `/v1/traces` | Exact | OpenTelemetry traces |
| `/v1/metrics` | Exact | OpenTelemetry metrics |
| `/otlp/v1/logs`, `/otlp/v1/traces`, `/otlp/v1/metrics` | Exact | OpenTelemetry signals at Loki's and Grafana Cloud's paths |
| `/api/prom/push` | Exact | Prometheus remote write at the Grafana Cloud/Cortex path |
| `/loki/api/v1` | Prefix | Loki push and queries |
| `/api/v1` | Prefix | Prometheus remote write and queries |
| `/api/search/tags`, `/api/v2/search/tags` | Exact | Experimental default/combined or explicitly scoped names, optionally parent-string-filtered complete hints (not exact upstream omission parity), or static intrinsic vocabulary; same default-off gate |
| `/api/search/tag`, `/api/v2/search/tag` | Prefix | Experimental scoped string/int64/bool/float values (nonfinite classes included), parent-filtered leading-dot three-owner values, stored intrinsic strings and exact integer event-time offsets; same default-off gate |
| `/api/search` | Exact | Experimental Tempo search; disabled by default (`tempoSearch.enabled`) |
| `/api/traces` | Prefix | Experimental Tempo v1 exact-ID trace lookup |
| `/api/v2/traces` | Prefix | Experimental Tempo v2 exact-ID trace lookup |
| `/api/metrics` | Prefix | TraceQL metrics (`query_range`, `query`); same default-off gate as Tempo search |
| `/api/echo`, `/api/status/buildinfo` | Exact | Tempo datasource health checks |
| `/mcp` | Exact | Model Context Protocol |

Requests for any other path, including `/metrics`, `/healthz`, and `/readyz`,
never reach Pulse through that ingress. If you write your own proxy rules, keep
an allowlist like this, and make sure the proxy normalizes paths before matching
so encoded or doubled slashes cannot reach `/metrics`. See
[self-monitoring](self-monitoring.md#exposure-and-independent-collection) for
details.

Example with ingress-nginx and cert-manager:

```yaml
ingress:
  enabled: true
  className: nginx
  host: pulse.example.com
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    nginx.ingress.kubernetes.io/proxy-body-size: 5m
  tls:
    - secretName: pulse-tls
      hosts: [pulse.example.com]
```

Raise the proxy's request body limit to at least 4 MiB, the largest body Pulse
accepts. Many proxies default to 1 MiB, which rejects large collector batches
before they reach Pulse.

## Probes, shutdown, and upgrades

- **Liveness** (`GET /healthz`) answers as long as the node can serve HTTP.
- **Readiness** (`GET /readyz`) returns `503` until a background check can list the
  bucket. The check runs every 15 seconds, so readiness never adds storage
  requests per probe. A wrong bucket name or credentials keep the pod unready;
  the reason is logged.
- **Shutdown**: the chart waits `preStopSleepSeconds` (5 by default) so load
  balancers stop routing to the pod, then gives Pulse the rest of
  `terminationGracePeriodSeconds` (30 by default) to finish in-flight requests.
  Pulse only acknowledges a batch after it is durable in the bucket, so
  collectors retry anything cut off mid-request.
- **Compatible upgrades** roll out one new pod before stopping the old one.
  Read release notes first. Crossing the source-start or stale-sample
  compatibility boundaries below requires a non-overlapping upgrade, not the
  default rolling strategy.
  Do not mix incompatible readers, writers, or compactors.
- **Retention worker shutdown**: when the worker runs (`retention.enabled` or a
  positive duration), the chart raises the
  effective termination grace to at least the pre-stop delay plus
  `retention.timeoutMs` plus 15 seconds, so a maintenance operation can finish.
  In `enforce` mode with a positive duration it uses
  `retention.migrationTimeoutMs` instead when that is longer (ten minutes by
  default), so a manifest conversion is not cut short.
  Stopping a node does not cancel storage calls already in flight; retention
  work resumes from the manifest on the next pass.

The pod runs as an unprivileged user with a read-only root filesystem. The only
writable path is an `emptyDir` at `/tmp` for runtime scratch files.

### Remote-write source-start storage compatibility

Upgrading from metric capability tuple `{1,2,1,1,1}` to `{2,2,1,1,1}` requires a
**fleet-wide maintenance pause**, not an ordinary `helm upgrade` under traffic.
Senders can already supply starts and the new ingress retains them immediately.
Block metric delivery, finish pending old keyed retries, stop every old metric
reader/writer/compactor, replace all participants, then resume. Otherwise old
compactors can erase starts and mixed-version retries can duplicate records.
Follow the complete [source-start upgrade procedure](metrics.md#remote-write-20-start-timestamps).

For one chart deployment, use `strategy.type: Recreate` and
`strategy.rollingUpdate: null` during this upgrade. That only prevents overlap
within that deployment: coordinate the maintenance pause across **all** releases,
standalone instances and maintenance workers sharing the bucket. Pausing only
compaction is insufficient. Do not roll back to readers or compactors that drop
the start column after source-start writes.

### Stale-sample storage compatibility

When upgrading from a release that rejected stale markers, NaN, and infinities,
**do not use the default rolling update**. New writers persist those values
immediately, while old readers and compactors cannot decode them. Collectors
send stale markers automatically when series disappear, so asking collectors
not to send them is not a safe rollout strategy.

For the chart's Deployments, use `Recreate` for this upgrade (with several instances or pools, scale every Deployment to zero first):

```yaml
strategy:
  type: Recreate
  rollingUpdate: null # Removes the chart's default rolling-update settings.
```

Render the chart first and verify that `strategy` has only `type: Recreate`.
Then upgrade to the new image/chart. The old pod must finish termination before
the new pod starts. If other processes write, read, or compact the same bucket,
stop them too before starting any new-version writer. Keep collector queues and
the reference destination running; ingestion is unavailable during the upgrade,
and collectors must retry unacknowledged requests within their retry horizon.
Verify readiness, finite and stale-sample queries, and independent monitoring
before expanding traffic. Compatible subsequent upgrades can restore the rolling
strategy.

**Rollback is not a simple image rollback after the first non-finite write.**
Retain a compatible Pulse version to read the existing bucket, and roll forward
with a fix or route collection/query traffic back to the reference destination.
Do not delete live objects or restore an older manifest to hide incompatible
records: that can lose acknowledged data. Returning the bucket to an older data
contract requires a separately validated data migration or a pre-upgrade backup
with an explicitly accepted loss/backfill procedure. Record this boundary in the
release's upgrade notes.

### Retention format boundary

Enforcing [retention](retention.md) converts each tenant/signal manifest to a
paged format that releases without retention cannot read. Before setting
`retention.mode: enforce`:

1. Upgrade to a release with retention while `retention.mode` is `observe` (the
   chart default), and let the rollout finish so no older pod remains. Stop or
   fence any other process that reads, writes or compacts the bucket with an
   older release.
2. Then change only `retention.mode` (and the durations) in a separate upgrade.
   Pods of the same release can overlap during that rolling update.

A release containing retention support does not by itself make it safe to
overlap older and newer versions once a prefix has been converted. After
conversion, rolling back to a release without retention is not supported; fix
forward instead.

### Paged manifest boundary

Starting with 1.27.0, `manifestFormat: paged` (the default) converts each flat
tenant/signal manifest to a paged format on its next ingest write. Releases
before 1.27.0 reject paged manifests and fail those requests rather than read or
overwrite them, so mixing versions cannot lose data, but older pods cannot serve
converted prefixes until they are replaced. A single-replica rolling update only
sees retryable ingest errors on the old pod during the overlap. To avoid them,
roll out with `manifestFormat: flat`, then set `paged` in a second upgrade once no
older pod remains. Rolling back below 1.27.0 after conversion is not supported.
See [manifest format](configuration.md#manifest-format).

### Native library compatibility

Pulse's object-storage client and telemetry codec are native libraries that must come from the same
release as the rest of the application. The container image compiles it from
source, so this only matters if you build Pulse yourself with precompiled
native artifacts: each release publishes artifacts built from its own source.
With the S3 backend, a node whose native library predates the storage
operations this release needs refuses to start and names the mismatch, instead
of failing ingest later. Every node also refuses a codec artifact that cannot
preserve rich OTLP log/metric metadata, validate typed OTLP trace metadata or
run bounded native trace-level search and Tempo v1/v2 trace export. Rebuild with `PULSE_NIF_FORCE_BUILD=1` or install the
artifacts that match the release.

### Immutable keyed ingestion upgrade

New S3 applications require object-store native API `{1,1,1,1}` (retention, keyed publication, snapshot GET,
asynchronous requests). Upgrade or drain **every writer**, including recording evaluators
and instances in other serving pools, before relying on create-only keyed
uploads. Local startup checks and Helm Recreate cannot fence old unconditional
writers. Byte-different retries now fail permanently with HTTP409 rather than
overwriting; this is not semantic cross-encoder recovery. Conflicts can block a
recording queue and mixed/incoherent old writers can leave
`segment_summary_mismatch` compaction failures. Read
[keyed ingestion](keyed-ingestion.md) before upgrading encoder dependencies or
attempting recovery; preserve coherent backups and do not rotate retry keys.

### Typed trace metadata compatibility

Before enriched/non-finite trace writes, pause ingress, drain legacy and
byte-service keyed retries and
upgrade every reader, writer and compactor sharing the bucket, including
independent instances and other Helm releases. Read the complete
[trace upgrade boundary](traces.md#typed-metadata-upgrade-boundary). A startup
check rejects stale codec artifacts but cannot fence already running old nodes.
`Recreate` only orders pods within its own rollout.

The physical Parquet columns are unchanged, but new trace payloads contain both
query-friendly attributes and a typed envelope. This roughly doubles attribute
bytes plus tag/pair overhead. Previously near-ceiling batches can receive permanent
413 responses, and compaction/full query limits are reached sooner. Reduce and
measure hard-capped collector batches; halving alone is not a safety proof.

Retain compatible images/native artifacts for rollback and coherent backups of
segments/manifests/pages. Old decode/re-encode paths can erase typed metadata;
an incompatible rollback after rich writes is not supported. Legacy type identity
cannot be backfilled by guessing from base64 strings.

## Sending telemetry

Every request carries the tenant's bearer token and, for HTTP ingestion, the
`X-Scope-OrgID` header, or Basic credentials of the form `<tenant>:<token>`. The receivers speak existing protocols, so collectors
need only a destination change.

| Signal | Endpoint | Formats |
| --- | --- | --- |
| Logs | `POST /loki/api/v1/push` | Loki protobuf (Snappy) or JSON, optionally gzip |
| Logs | `POST /v1/logs` | OpenTelemetry Protocol over HTTP, protobuf or JSON, optionally gzip. Also served at `/otlp/v1/logs` (Loki's and Grafana Cloud's OTLP path), as are `/otlp/v1/metrics` and `/otlp/v1/traces`. See [typed logs, collector bridging and upgrades](logs.md). |
| Traces | `POST /v1/traces` | OpenTelemetry Protocol over HTTP, protobuf or JSON, optionally gzip. See [trace collector configuration and limits](traces.md). |
| Metrics | `POST /api/v1/write` | Prometheus remote write 1.0 and 2.0 (chosen by the `Content-Type` `proto` parameter). Also served at `/api/prom/push` (Grafana Cloud, Cortex) and `/api/v1/push` (Mimir). |
| Metrics | `POST /v1/metrics` | OTLP/HTTP JSON/protobuf, optionally gzip. Gauges, cumulative sums, cumulative explicit histograms and summaries; see [supported metrics and collector configuration](metrics.md). |

OTLP/gRPC for logs, metrics and traces is available on a separate, opt-in port; see [OTLP over gRPC](otlp-grpc.md).
All OTLP receivers additionally require matching application/native artifacts
with shared **OTLP wire capability 3** for bounded message merging, exact quoted/
unquoted integer forms and receiver-scoped duplicate JSON validation. Fractional timestamps can no longer underflow into an
unknown-time/receive-time fallback. Known duplicate JSON fields now return 400
instead of silently selecting the first field; unknown fields stay ignored in
the receiving signal's schema. Upgrade every serving ingress pair before relying on those forms;
there is no storage-format change in this wire increment. See [wire upgrade and
rollback](otlp-wire.md#upgrade-and-rollback).

For delta or exponential-histogram workloads, keep a compatible metric backend. Upgrade every serving ingress app/native pair to OTLP decoder capability 2 before relying on explicit histograms/summaries; an older pool rejects those points. Both source-point and expanded-sample limits apply, and repeated full source envelopes still obey the fixed 16 MiB metadata ceiling. See [distribution behavior and batching](metrics.md#histograms-and-summaries).
Upgrade all metric readers, writers and compactors before metadata-bearing OTLP
metric writes; see [metrics upgrade and rollback](metrics.md#upgrade-and-rollback).
Rich OTLP log writes require all readers/writers upgraded and pending legacy
keyed retries drained first; see [log storage compatibility](logs.md#upgrade-and-rollback).

[Grafana Alloy](https://grafana.com/docs/alloy/latest/) example, using the
in-cluster Service:

```alloy
loki.write "pulse" {
  endpoint {
    url          = "http://pulse.observability.svc:4000/loki/api/v1/push"
    tenant_id    = "production"
    bearer_token = sys.env("PULSE_TOKEN")
  }
}

prometheus.remote_write "pulse" {
  endpoint {
    url          = "http://pulse.observability.svc:4000/api/v1/write"
    headers      = { "X-Scope-OrgID" = "production" }
    bearer_token = sys.env("PULSE_TOKEN")
  }
}
```

Alloy's `prometheus.remote_write` sends metric metadata (type, help, unit) only
over Remote Write 2.0, and only for scrapes with `honor_metadata = true`. Both
are experimental in Alloy, so run it with `--stability.level=experimental`:

```alloy
prometheus.scrape "app" {
  // ...
  honor_metadata = true
  forward_to     = [prometheus.remote_write.pulse.receiver]
}

prometheus.remote_write "pulse" {
  endpoint {
    url              = "http://pulse.observability.svc:4000/api/v1/write"
    protobuf_message = "io.prometheus.write.v2.Request"
    headers          = { "X-Scope-OrgID" = "production" }
    bearer_token     = sys.env("PULSE_TOKEN")
  }
}
```

Over Remote Write 2.0, Pulse answers with the
`X-Prometheus-Remote-Write-*-Written` counts. A request with invalid series or
invalid histograms stores its valid series and answers 400 (as Prometheus
does), so the sender counts the rest as failed; invalid exemplars are dropped
and left out of the written count. Prometheus itself sends metadata over both
versions. To send native histograms and exemplars, set `send_native_histograms`
and `send_exemplars` on the remote write (Prometheus, Alloy's
`prometheus.remote_write`) and scrape native histograms at the source.

OpenTelemetry Collector example for logs:

```yaml
exporters:
  otlphttp/pulse:
    logs_endpoint: http://pulse.observability.svc:4000/v1/logs
    encoding: json
    headers:
      Authorization: Bearer ${env:PULSE_TOKEN}
      X-Scope-OrgID: production
```

Pulse rejects a whole batch with `413` when it exceeds the
[ingest limits](ingest-limits.md); shrink the collector's batch size if that
happens. When adding Pulse next to an existing backend, give each destination
its own retry queue so a problem with one does not hold back the other.

To check that Pulse answers like the existing backend while both receive the
same data, run `mix pulse.parity` from a Pulse checkout. It takes Grafana
dashboard JSON exports, Grafana alert rule exports or a plain list of queries,
runs every PromQL and LogQL query over several windows (default 1h, 6h, 24h,
7d) against both backends with identical step-aligned bounds, and reports
series or streams that differ, values beyond a relative tolerance (default
1e-9) and errors on either side, exiting non-zero if any. Credentials go in
`PULSE_PARITY_REFERENCE_HEADERS` and `PULSE_PARITY_CANDIDATE_HEADERS` (one
`Name: value` per line); `mix help pulse.parity` lists the options.

## Querying

- **Model Context Protocol**: point an agent at `https://<host>/mcp` with the
  bearer token. Pulse implements the stateless `2026-07-28` revision of the
  protocol over Streamable HTTP; clients that only speak older revisions receive
  `400` with the supported version.
- **Prometheus API**: `GET|POST /api/v1/query` and `/api/v1/query_range`, with
  the same token and tenant header. Grafana can use it as a Prometheus data
  source for the [supported query subset](querying.md#prometheus-api).
  Bounded label/value/series discovery is also available through `/api/v1/labels`,
  `/api/v1/label/<name>/values` and `/api/v1/series`; see [metadata API limits](metric-discovery.md).
  Serving app/native pairs require metric codec `{2,2,1,1,1}` (including source-start retention and footer planning). These routes do not
  establish complete Grafana datasource/client compatibility.
- **Loki API**: `/loki/api/v1/query`, `query_range`, `labels`, and
  `label/<name>/values`.

## Monitoring Pulse

Scrape `GET /metrics` on every node from a monitoring system other than Pulse.
Set `serviceMonitor.enabled=true` if you run the Prometheus Operator. See
[self-monitoring](self-monitoring.md) for the metrics and suggested queries.

## Running without Kubernetes

The image runs anywhere containers do. Pass the [configuration](configuration.md)
as environment variables:

```sh
docker run -d --name pulse -p 127.0.0.1:4000:4000 \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PULSE_TENANT_TOKENS='{"production":"sha256$<digest>"}' \
  -e PULSE_S3_BUCKET=pulse-telemetry \
  -e PULSE_S3_REGION=us-east-1 \
  -e PULSE_S3_ACCESS_KEY_ID=AKIA... \
  -e PULSE_S3_SECRET_ACCESS_KEY=... \
  ghcr.io/tuist/pulse:<version>
```

Put a TLS-terminating proxy in front of it with the same path allowlist described
in [Networking and TLS](#networking-and-tls).
