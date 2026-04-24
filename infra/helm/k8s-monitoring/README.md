# Grafana Kubernetes Monitoring for the Tuist managed cluster

Wraps [`grafana/k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) (v4) so the Tuist-managed workload clusters forward not just the app telemetry but the full Kubernetes picture — cluster/pod/node metrics, cluster events, and the standard labels the Grafana Cloud **Kubernetes** app expects.

Supersedes [`infra/helm/alloy/`](../alloy/). Same destinations (Grafana Cloud Prometheus / Loki / Tempo), same 1Password-via-ESO token sync, broader coverage.

## What this adds over the old chart

| Signal | Old (`helm/alloy`) | New (`helm/k8s-monitoring`) |
|---|---|---|
| Server app metrics | Static scrape of the `tuist-tuist-server` Service `/metrics` | Auto-discovered via `prometheus.io/scrape=true` annotation already on the server pods |
| Server traces | OTLP gRPC on :4317 → Tempo | Same, via `alloy-receiver` |
| Server logs | stdout tailed via kubelet API → Loki | stdout tailed via DaemonSet `/var/log/pods` → Loki (narrower blast radius) |
| **kube-state-metrics** | — | Deployed + scraped (workload/pod/deployment/replica state) |
| **node-exporter** | — | Deployed as DaemonSet (node CPU/mem/disk/net) |
| **kubelet + cAdvisor** | — | Scraped (container resource usage) |
| **Kubernetes Events** | — | Streamed to Loki as structured logs |

With all four the Grafana Cloud **Observability → Kubernetes** app lights up (Cluster / Namespace / Workload / Pod / Node views) without importing dashboards by hand.

## Install

Installed automatically by the `observability-install` job in [`.github/workflows/server-deployment.yml`](../../../.github/workflows/server-deployment.yml) — it runs before every server deploy and is idempotent, so the chart tracks whatever's committed on `main`. The first deploy against a new cluster brings it up; subsequent deploys are no-op upgrade checks.

Manual install (only needed when bootstrapping a fresh cluster ahead of the first CI deploy, or iterating locally):

```bash
helm dependency update infra/helm/k8s-monitoring
helm upgrade --install k8s-monitoring infra/helm/k8s-monitoring \
  -n observability --create-namespace \
  -f infra/helm/k8s-monitoring/values-staging.yaml
```

Prerequisites:

1. **ClusterSecretStore `onepassword` exists.** Installed once per workload cluster as part of the Tuist chart bootstrap — see [`k8s/syself-onboarding.md`](../../k8s/syself-onboarding.md) §5.
2. **1Password items** present in the cluster's vault:

   | Item name | Category | Field |
   |---|---|---|
   | `PROMETHEUS_TOKEN` | Password | `password` |
   | `LOKI_TOKEN` | Password | `password` |
   | `TEMPO_TOKEN` | Password | `password` |

3. **Grafana Cloud endpoints / usernames** — baked into `values.yaml`. Sanity-check they match the stack before installing a fresh cluster.
4. **Worker nodes sized for the footprint.** Four Alloy DaemonSets × 2 workers + kube-state-metrics + node-exporter want ~1.5 GB per node on top of the app. Staging/canary clusters run on `cpx31` (8 GB/node), production on `ccx23` (16 GB/node). `cpx22` (4 GB) is too small — a rolling server update can't fit a fresh pod alongside the old one while the Alloy DaemonSets are pinned to the node.

## Server-side wiring

The managed Tuist server pushes OTLP spans to Alloy. With this chart the receiver Service moves from the old name to:

```
http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4317
```

`infra/helm/tuist/values-managed-{staging,canary,production}.yaml` already point `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` at this address — confirm after a chart bump.

Server pod metrics are discovered automatically: the server Deployment carries `prometheus.io/scrape: "true"` and `prometheus.io/port: "9091"`, and `annotationAutodiscovery` picks those up without any static scrape-target config.

## What gets deployed

Four Alloy instances, split by role (managed by the upstream `alloy-operator`):

- `alloy-metrics` — scrapes metrics (cluster / node / app) ; runs clustered so replicas hash-partition targets
- `alloy-logs` — DaemonSet tailing pod logs from `/var/log/pods`
- `alloy-singleton` — cluster events (singleton so events aren't duplicated)
- `alloy-receiver` — OTLP gRPC receiver for the server's traces

Plus the telemetry services themselves:

- `kube-state-metrics` Deployment
- `node-exporter` DaemonSet

## Local validation

```bash
helm dependency update infra/helm/k8s-monitoring
helm lint infra/helm/k8s-monitoring -f infra/helm/k8s-monitoring/values-staging.yaml
helm template k8s-monitoring infra/helm/k8s-monitoring \
  -n observability \
  -f infra/helm/k8s-monitoring/values-staging.yaml \
  | kubectl apply --dry-run=client -f -
```

## Verify it's working after install

```bash
# All four Alloy StatefulSets / DaemonSets ready
kubectl -n observability get alloy,statefulset,daemonset

# Grafana Cloud token secret materialized
kubectl -n observability get externalsecret,secret k8s-monitoring-grafana-cloud

# Alloy-receiver is listening on :4317
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

The old chart added `env` + `service_name=tuist-server` labels on every signal. Here the server signals get labeled via the upstream chart's k8s attribute processor, which expands automatically from pod metadata — no hand-rolled relabel rules.

## RBAC — what access does this chart get?

Broader than the old chart (which only needed `pods/log` via kubelet proxy). The new split:

- `alloy-metrics` — cluster-wide `get/list/watch` on nodes/pods/services/endpoints for target discovery, plus `/metrics/cadvisor` on kubelets.
- `alloy-logs` — node-local hostPath to `/var/log/pods`. A compromised pod can only read logs from the single node it runs on (narrower than the old kubelet-proxy model).
- `alloy-singleton` — cluster-wide `get/list/watch` on events.
- `alloy-receiver` — none beyond standard pod execution.
- `kube-state-metrics` — cluster-wide read on most core/apps/batch objects (standard for KSM).
- `node-exporter` — hostPID, `/proc` / `/sys` hostPath (standard for node_exporter).

All cluster-wide reads are metadata only. Grafana Cloud tokens remain in the ESO-managed Secret, not mounted as files.
