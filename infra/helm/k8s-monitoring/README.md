# Grafana Kubernetes Monitoring for the Tuist managed cluster

Wraps [`grafana/k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) (v4) so the Tuist-managed workload clusters forward the full Kubernetes telemetry picture to Grafana Cloud. What you get out of the box:

| Signal | Source |
|---|---|
| Server app metrics | Auto-discovered via `prometheus.io/scrape=true` annotation on the server pods |
| Server traces | OTLP gRPC :4317 → Grafana Cloud Tempo |
| Server logs | stdout tailed from `/var/log/pods` by a per-node Alloy DaemonSet → Grafana Cloud Loki |
| kube-state-metrics | Deployed + scraped (workload / pod / deployment / replica state) |
| node-exporter | Deployed as DaemonSet (node CPU / mem / disk / net) |
| kubelet + cAdvisor | Scraped (container resource usage) |
| Kubernetes Events | Streamed to Loki as structured logs |
| Alert rules | YAML under [`alerts/`](./alerts) synced to Grafana Cloud Mimir on every `helm upgrade` (see [Alerting](#alerting)) |

With these in place the Grafana Cloud **Observability → Kubernetes** app populates automatically (Cluster / Namespace / Workload / Pod / Node views) without importing dashboards by hand.

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

The managed Tuist server pushes OTLP spans to the `alloy-receiver` Service:

```
http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4317
```

`infra/helm/tuist/values-managed-{staging,canary,production}.yaml` set `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` to this address.

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

## Alerting

Grafana Cloud Mimir evaluates alert rules server-side, so there is no in-cluster Prometheus or Alertmanager to configure. Rule groups live as YAML files under [`alerts/`](./alerts) in this chart and are pushed to Mimir on every `helm upgrade` by a Job that runs `mimirtool rules sync` against the same Grafana Cloud stack metrics flow into. The Job authenticates with the existing `prometheus-username` / `prometheus-password` keys from the ESO-managed Grafana Cloud Secret — no extra credentials.

Each YAML file under `alerts/` is a self-contained Mimir rule namespace (`namespace:` at the top, `groups:` below). `mimirtool rules sync` is declarative: rules in the file get created or updated, rules in Mimir not present in the file get deleted, so the file is the source of truth for that namespace. Rolling back a whole rule namespace is `mimirtool rules delete-namespace <name>` against the same endpoint.

The sync runs from every environment install. Mimir's ruler API doesn't shard by tenant on push (single Grafana Cloud stack across staging / canary / production), so the redundant runs converge on the same target state and self-heal if Mimir's view ever drifts. If you want to disable the sync for a specific environment, set `alertRules.enabled: false` in that overlay.

To add a new rule:

1. Drop a `<name>.yaml` file under `alerts/` with the rule namespace and groups.
2. `helm template ...` to confirm it renders into the ConfigMap (see [Local validation](#local-validation)).
3. `mimirtool rules check alerts/<name>.yaml` to lint the PromQL.
4. Open a PR — the next deploy syncs it.

`alerts/ingress-nginx.yaml` covers the `tuist-tuist-server` Ingress and is intentionally scoped — see the file header for the rationale and aggregation choices.

## Label conventions (for dashboards / queries)

| Label / attribute | Where it's set | Applies to |
|---|---|---|
| `cluster` / `k8s.cluster.name` | `k8s-monitoring.cluster.name` in overlays | metrics, logs, traces |
| `env` | `destinations.*.extraLabels` in overlays | metrics, logs (Loki/Prometheus external labels) |
| `deployment.environment` | `destinations.grafana-cloud-traces.processors.attributes.actions` in overlays | traces (OTLP resource attribute) |

Server-level labels (`namespace`, `pod`, `container`, deployment/statefulset names) are attached automatically by the upstream chart's k8s attribute processor from pod metadata.

## RBAC — what access does this chart get?

- `alloy-metrics` — cluster-wide `get/list/watch` on nodes/pods/services/endpoints for target discovery, plus `/metrics/cadvisor` on kubelets.
- `alloy-logs` — node-local hostPath to `/var/log/pods`. A compromised pod can only read logs from the single node it runs on.
- `alloy-singleton` — cluster-wide `get/list/watch` on events.
- `alloy-receiver` — none beyond standard pod execution.
- `kube-state-metrics` — cluster-wide read on most core/apps/batch objects (standard for KSM).
- `node-exporter` — hostPID, `/proc` / `/sys` hostPath (standard for node_exporter).

All cluster-wide reads are metadata only. Grafana Cloud tokens remain in the ESO-managed Secret, not mounted as files.
