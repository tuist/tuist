# Grafana Kubernetes Monitoring for the Tuist managed cluster

Wraps [`grafana/k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) (v4) so the Tuist-managed workload clusters forward the full Kubernetes telemetry picture to Grafana Cloud. What you get out of the box:

| Signal | Source |
|---|---|
| Server app metrics | Auto-discovered via `prometheus.io/scrape=true` annotation on the server pods |
| Application traces | OTLP gRPC :4317 for server/processor and OTLP HTTP :4318 for managed Kura → Grafana Cloud Tempo |
| Server logs | stdout tailed from `/var/log/pods` by a per-node Alloy DaemonSet → Grafana Cloud Loki |
| Node logs | host journald (`containerd`, `kubelet`, kernel) read from `/var/log/journal` by the same DaemonSet → Grafana Cloud Loki |
| kube-state-metrics | Deployed + scraped (workload / pod / deployment / replica state) |
| node-exporter | Deployed as DaemonSet (node CPU / mem / disk / net) |
| kubelet + cAdvisor | Scraped (container resource usage) |
| Kubernetes Events | Streamed to Loki as structured logs |
| Kubernetes control endpoint | Request latency, requests in flight, rejected requests, and scrape availability |
| etcd | Leader state, commit latency, write-ahead-log synchronization latency, and peer round-trip time |
| Stable outbound gateway | Controller reconciliation plus active and prepared gateway state |
| Management cluster | Desired, current, ready, available, and up-to-date control-plane replicas |
| Hetzner load balancers | Target health, connections, requests, and inbound/outbound bandwidth |

With these in place the Grafana Cloud **Observability → Kubernetes** app populates automatically (Cluster / Namespace / Workload / Pod / Node views) without importing dashboards by hand.

The recommended incident alerts and Grafana setup steps are in
[`alerts.md`](alerts.md).

## Install

Installed automatically by the `observability-install` job in [`.github/workflows/server-deployment.yml`](../../../.github/workflows/server-deployment.yml) for the managed workload clusters. The path is idempotent, so the chart tracks whatever's committed on `main`.

Manual install (only needed when bootstrapping a fresh cluster ahead of the first CI deploy, or iterating locally):

```bash
helm dependency build infra/helm/k8s-monitoring
helm upgrade --install k8s-monitoring infra/helm/k8s-monitoring \
  -n observability --create-namespace \
  -f infra/helm/k8s-monitoring/values-staging.yaml
```

The Cluster API management cluster is installed by
`.github/workflows/mgmt-cluster-apply.yml` with `values-management.yaml`. Its
`tuist-k8s-mgmt` 1Password vault must contain a `PROMETHEUS_TOKEN` password
item. The workflow creates only the metrics destination Secret; logs and traces
are intentionally disabled on that small cluster. The Hetzner load-balancer
exporter reuses the existing `org-tuist/hetzner` Secret and its `hcloud` key
that the Cluster API provider already requires.

During credential-access recovery, the workflow can preserve an existing
`observability/k8s-monitoring-grafana-cloud` Secret when the service account
cannot read `PROMETHEUS_TOKEN`. This does not make the credential optional for
new clusters: the workflow fails before applying infrastructure when neither
the 1Password item nor the exact existing Secret with the expected username is
available. Once the management vault item is readable, the next run refreshes
the Secret from 1Password automatically. Before applying anything, the workflow
probes Grafana's remote-write endpoint and rejects a revoked credential. The
post-apply check also requires a fresh successful remote write, so an
incorrectly configured collector fails the workflow even when every collector
Pod is running.

The management cluster enforces the baseline
[Pod Security Standard](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
by default. `infra/k8s/mgmt/observability-namespace.yaml` grants only the
`observability` namespace the host access required by the node and
control-plane collectors. Restricted-mode audit events and warnings remain
enabled there and are pinned to the management cluster's Kubernetes minor
version. Do not deploy unrelated workloads into this privileged namespace.

Prerequisites:

1. **ClusterSecretStore `onepassword` exists.** Installed once per workload cluster as part of the bootstrap — see [`k8s/onboarding.md`](../../k8s/onboarding.md) §4.
2. **1Password items** present in the cluster's vault:

   | Item name | Category | Field |
   |---|---|---|
   | `PROMETHEUS_TOKEN` | Password | `password` |
   | `LOKI_TOKEN` | Password | `password` |
   | `TEMPO_TOKEN` | Password | `password` |

3. **Grafana Cloud endpoints / usernames** — baked into `values.yaml`. Sanity-check they match the stack before installing a fresh cluster.
4. **Worker nodes sized for the footprint.** The Alloy collectors, kube-state-metrics, and node-exporter want ~1.5 GB per node on top of the app. Staging/canary clusters run on `cpx31` (8 GB/node), production on `ccx23` (16 GB/node). `cpx22` (4 GB) is too small — a rolling server update can't fit a fresh pod alongside the old one while the node-local collectors are pinned to the node.

## Workload-side wiring

The managed Tuist server and processor push OTLP gRPC spans to the `alloy-receiver` Service:

```
http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4317
```

`infra/helm/tuist/values-managed-{staging,canary,production}.yaml` set `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` to this address.

Managed Kura pods push OTLP HTTP spans to the same Service:

```
http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4318/v1/traces
```

`infra/helm/tuist/values-managed-common.yaml` passes this endpoint to the Kura controller, which injects it into controller-managed Kura pods unless a `KuraInstance` overrides it explicitly.

Server pod metrics are discovered automatically: the server Deployment carries `prometheus.io/scrape: "true"` and `prometheus.io/port: "9091"`, and `annotationAutodiscovery` picks those up without any static scrape-target config.

### The macOS fleet pushes logs to `alloy-receiver:3100`

The same receiver serves a `loki.source.api` on 3100 for everything running on a Mac mini, because none of it can be tailed from the cluster:

- The **Tart guests** (xcresult processor) — Alloy cannot read a VM's filesystem, and `kubectl logs` cannot resolve their tailnet-only kubelet hostnames.
- The **Mac mini hosts themselves** — a Pod scheduled to a macOS Node *is* a Tart VM, so a DaemonSet-shaped collector lands inside a guest and never sees `/var/log/tart-kubelet.log`. The host runs [`infra/macos-log-shipper`](../../macos-log-shipper) instead, installed by the CAPI provider's bootstrap alongside `node_exporter`. Query it as `{job="tuist-macos-tart-kubelet"}`.

Both reach it at the receiver Service's **tailnet** hostname, set by the `tailscale.com/expose` annotations in each env's `values-{staging,canary,production}.yaml`, not at the in-cluster address Linux workloads use. Pushing here rather than to Grafana Cloud keeps the ingest credential in one place: Alloy forwards with the token it already holds, so no Mac mini carries one and the tailnet ACL is the access control.

## What gets deployed

Six Alloy instances, split by role (managed by the upstream `alloy-operator`):

- `alloy-metrics` — scrapes metrics (cluster / node / app) ; runs clustered so replicas hash-partition targets
- `alloy-logs` — DaemonSet tailing pod logs from `/var/log/pods`, plus host journald from `/var/log/journal` (node logs feature, scoped to `containerd` / `kubelet` / kernel)
- `alloy-singleton` — cluster events (singleton so events aren't duplicated)
- `alloy-receiver` — OTLP gRPC and HTTP receiver for managed workload traces
- `grafana-cloud-traces-sampler` — keeps failed, slow, and sampled healthy
  traces before they are sent to Grafana Cloud
- `alloy-control-plane` — one host-networked Pod per control-plane node,
  scraping the local Kubernetes and etcd endpoints without exposing etcd
  outside the machine

The management cluster runs only `alloy-metrics` and `alloy-control-plane`.
It also runs a Hetzner load-balancer exporter and configures kube-state-metrics
to expose `KubeadmControlPlane` replica state.

Plus the telemetry services themselves:

- `kube-state-metrics` Deployment
- `node-exporter` DaemonSet

## Metrics aggregated downstream of this chart

What this chart keeps is not what Grafana Cloud stores. **Adaptive Metrics** sits
in front of the tenant and rewrites series on ingest, so a metric can be
allow-listed here, present in the collector's deployed config, and still be
unqueryable in the shape a dashboard or alert needs. Check it before concluding
the chart is at fault.

Its rules are query-driven: it proposes aggregating away any label no query has
touched in the lookback, and **auto-apply is enabled on this stack**, so a
recommendation becomes a rule on its own. That means a metric nobody queries
loses its labels, and a query is the only thing that keeps them.

An aggregated metric does not disappear. It survives as a single series with the
aggregated labels removed, which is why a matcher on one of them silently
matches nothing:

```
{__name__="node_memory_Cached_bytes", cluster="tuist-production"}   # no data
sum(node_memory_Cached_bytes)                                       # a number
node_memory_Cached_bytes                                            # errors, and names every aggregated label
```

The bare query is the fastest audit: the error lists exactly which labels are
gone.

Read and edit the rules through the tenant's own endpoint, authenticated as the
metrics tenant rather than as the Grafana instance. A Grafana stack
service-account token is the wrong credential here; the env vault's `LOKI_TOKEN`
is an access policy token that carries tenant read:

```bash
TOKEN=$(op read "op://tuist-k8s-production/LOKI_TOKEN/password")
BASE=https://prometheus-prod-24-prod-eu-west-2.grafana.net

# Current rules, and whether recommendations auto-apply
curl -s -u "1774467:$TOKEN" $BASE/aggregations/rules > rules.json
curl -s -u "1774467:$TOKEN" $BASE/aggregations/recommendations/config
```

`POST /aggregations/rules` replaces the **entire** rule set, so edit the file
rather than sending a fragment, and pass the `Etag` from the GET as `If-Match`
so a concurrent change fails instead of being clobbered. Keep the GET response
as the rollback. Ingest picks the change up within about fifteen minutes;
already-stored samples stay aggregated, so verify on fresh data.

Deleting a rule is not durable on its own while auto-apply is on. The
recommendation that produced it stands until a query touches the metric again,
and the next cycle reapplies it. Pair every deletion with the query that
protects it, which for Kura page cache is the **Page cache by node** panel in
`infra/grafana-dashboards/tuist-kura-region-scalability.json`.

`recommendations/config` also carries a global `keep_labels` list: a label named
there is never proposed for aggregation on any metric. It is empty today.
Putting `cluster` in it would end this whole class of bug, at the cost of every
future recommendation that would have dropped `cluster` for real savings.

Restoring a label restores its cardinality. `node_memory_Cached_bytes` and
`node_memory_MemFree_bytes` are 59 hosts each, so about 120 series and a dollar
a month at the stack's measured rate.

## Metrics scrape cadence

Cluster and custom metrics jobs normally use a 60-second scrape interval. The
local control-plane jobs use 30 seconds so a short control-plane interruption
still produces enough samples to distinguish process, storage, and network
pressure. The one-minute default
matches Grafana Cloud's included rate of one data point per minute for each
active series, while keeping enough resolution for the infrastructure
dashboards and alerts. Keep other job-specific overrides at 60 seconds unless a
documented operational requirement justifies the additional ingestion cost.
See [Grafana's scrape interval guidance](https://grafana.com/docs/grafana-cloud/cost-management-and-billing/analyze-costs/reduce-costs/metrics-costs/adjust-data-points-per-minute/).

## Metrics cost controls

Grafana Cloud bills metrics per active series, so cardinality is the cost
driver. The plan includes 10,000 series; everything above that is overage.

Three layers trim what leaves the cluster, cheapest first:

1. **Per-feature allow-lists** (`<feature>.metricsTuning`). `useDefaultAllowList`
   plus explicit `includeMetrics` / `excludeMetrics`. This is where a metric
   family that no dashboard or alert reads should be removed.
2. **Per-feature relabeling** (`extraMetricProcessingRules`,
   `extraDiscoveryRules`). Used to drop a namespace or a label value rather
   than a whole metric, e.g. pod-scoped kube-state metrics for
   `tuist-runners`.
3. **Destination write relabeling** (`destinations.grafana-cloud-metrics.metricProcessingRules`).
   Last stop, applied to every feature at once. Drops restart-scoped labels
   and histogram buckets outside production.

Histogram buckets are the single largest shape, around a third of all billable
series, and their cardinality tracks route and worker coverage rather than
traffic. They are dropped for `tuist-staging`, `tuist-canary` and
`tuist-pentest`. `_count` and `_sum` survive, so request rates and mean
latency still work everywhere; `histogram_quantile` percentiles are
production-only.

Two cost levers are **not** chart values and have to be changed on the stack:

| Lever | Where |
|---|---|
| `traces_service_graph_*` series (~3.4k) | Tempo → Metrics generator → service graphs. Generated from received spans inside Grafana Cloud, so they never pass through Alloy and no `write_relabel_config` here can drop them. |
| Adaptive Metrics aggregation rules | Grafana Cloud → Adaptive Metrics. Recommendations need a Cloud access policy token; the stack API token used by dashboards cannot read them. |

To see what is actually costing money, query the cardinality API rather than
guessing:

```bash
curl -s -u "$GRAFANA_USER:$GRAFANA_TOKEN" \
  "$PROM_URL/api/v1/cardinality/label_values?label_names\[\]=__name__&limit=100"
```

Swap `__name__` for `cluster` or `job` to attribute series to an environment or
a scrape target, and add `selector={cluster="tuist-staging"}` to scope it.

## Log and trace sampling

Routine request logs are sampled before they leave the cluster. The pipeline
keeps 10 percent of the single structured completion entry emitted for Tuist
requests with response codes from 200 through 399. It also keeps 10 percent of
Kura ingress responses with codes from 200 through 299 or 404. The standalone
cache hosts apply the same rate to completion entries with response codes from
200 through 299 or 404. Every warning, error, and unusual response remains
unsampled.

Application traces use [tail sampling](https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.processor.tail_sampling/).
The sampler keeps every trace marked as an error, every trace lasting more than
two seconds, and 25 percent of the remaining healthy traces. Production runs
two sampler replicas; staging and canary run one. Trace collection and the
sampler remain disabled in the management cluster.

## Local validation

```bash
helm dependency build infra/helm/k8s-monitoring
helm lint infra/helm/k8s-monitoring -f infra/helm/k8s-monitoring/values-staging.yaml
helm template k8s-monitoring infra/helm/k8s-monitoring \
  -n observability \
  -f infra/helm/k8s-monitoring/values-staging.yaml \
  | kubectl apply --dry-run=client -f -

helm lint infra/helm/k8s-monitoring -f infra/helm/k8s-monitoring/values-management.yaml
helm template k8s-monitoring infra/helm/k8s-monitoring \
  -n observability \
  -f infra/helm/k8s-monitoring/values-management.yaml \
  | kubectl apply --dry-run=client -f -
```

## Verify it's working after install

```bash
# All Alloy workloads ready
kubectl -n observability get alloy,statefulset,daemonset

# Grafana Cloud token secret materialized
kubectl -n observability get externalsecret,secret k8s-monitoring-grafana-cloud

# Alloy-receiver is listening on :4317 and :4318
kubectl -n observability get svc k8s-monitoring-alloy-receiver

# Cluster metrics flowing (check from inside alloy-metrics pod)
kubectl -n observability port-forward svc/k8s-monitoring-alloy-metrics 12345:12345 &
curl -s http://localhost:12345/metrics | grep 'prometheus_remote_storage_samples_total{'
```

In Grafana Cloud: **Observability → Kubernetes → Cluster navigation** and pick the cluster by name (`tuist-staging` / `tuist-canary` / `tuist-production`).

## Label conventions (for dashboards / queries)

| Label / attribute | Where it's set | Applies to |
|---|---|---|
| `cluster` / `k8s.cluster.name` | `k8s-monitoring.cluster.name` in overlays | metrics, logs, traces |
| `env` | `destinations.*.extraLabels` in overlays | metrics, logs (Loki/Prometheus external labels) |
| `deployment.environment` | `destinations.grafana-cloud-traces.processors.attributes.actions` in overlays | traces (OTLP resource attribute) |

Server-level labels (`namespace`, `pod`, `container`, deployment/statefulset names) are attached automatically by the upstream chart's k8s attribute processor from pod metadata.

### Kura metric identity across rollouts

For `job="kura"` with nonempty `namespace` and `pod` labels, the metrics
destination rewrites `instance` to `<namespace>/<pod>`. The existing `cluster`
label separates environments, and the StatefulSet pod name separates replicas
while surviving pod replacement. Scraping still uses the pod IP; only the
stored metric label changes.

This applies to both Ready annotation-autodiscovery and the custom unready
scrape, including `up` and `scrape_*`. Keep `ready="false"` on the unready path:
it prevents those samples from colliding with Ready samples during discovery
handoff. Targets without a complete pod identity and other jobs are unchanged.

Using the IP as `instance` previously created a new set of series on every
replacement. During the September 7, 2026 production rollout, repeated Kura
replacements drove active series from roughly 142,000 to 216,000 while old
series remained active for Grafana Cloud's 20-minute window. The first deploy
of this rule also creates a one-time identity transition; later replacements
reuse the stable identity. Counter resets remain visible to `rate`/`increase`.
The Kura dashboard discovers instance values from metrics, so it picks up the
new identities automatically. Queries pinned to an IP must use the pod identity
instead.

## RBAC — what access does this chart get?

- `alloy-metrics` — cluster-wide `get/list/watch` on nodes/pods/services/endpoints for target discovery, plus `/metrics/cadvisor` on kubelets.
- `alloy-control-plane` — one host-networked pod on each control-plane node, with read-only access to the Kubernetes `/metrics` endpoint. etcd metrics remain on the host loopback interface.
- `alloy-logs` — node-local hostPath to `/var/log/pods` (pod logs) and `/var/log/journal` (host journald: `containerd` / `kubelet` / kernel). No extra Kubernetes API access; a compromised pod can still only read logs from the single node it runs on.
- `alloy-singleton` — cluster-wide `get/list/watch` on events.
- `alloy-receiver` — none beyond standard pod execution.
- `kube-state-metrics` — cluster-wide read on most core/apps/batch objects (standard for KSM).
- `node-exporter` — hostPID, `/proc` / `/sys` hostPath (standard for node_exporter).

All cluster-wide reads are metadata only. Grafana Cloud tokens remain in the ESO-managed Secret, not mounted as files.
