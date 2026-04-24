# Grafana Alloy for the Tuist managed cluster (DEPRECATED)

**Superseded by [`infra/helm/k8s-monitoring/`](../k8s-monitoring/README.md).** The new chart covers the same telemetry paths (Grafana Cloud Prometheus / Loki / Tempo, same ESO token sync) plus cluster / pod / node metrics and events, so the Grafana Cloud Kubernetes app works out of the box.

## Cutover / cleanup

Cleanup is deliberately manual — `helm uninstall` is destructive and the cutover per cluster is a one-time event, so it doesn't belong in the every-deploy CI workflow. Once the new receiver is live on a cluster and the server is pushing traces to it, drop the old release:

```bash
export KUBECONFIG=~/.kube/<env>.yaml
helm uninstall alloy -n observability
```

After all three clusters (staging, canary, production) have been cut over, delete this directory + any remaining references in a follow-up PR.

---

In-cluster telemetry collector. Forwards metrics, logs, and traces from the Tuist workloads to Grafana Cloud.

## What it does

| Signal | Path |
|---|---|
| **Metrics** | `prometheus.scrape` pulls `/metrics` on the server Service every 30s, `prometheus.remote_write` pushes to Grafana Cloud Prometheus. |
| **Traces** | `otelcol.receiver.otlp` listens on `:4317` (gRPC). Server's OTLP exporter pushes spans here. `otelcol.exporter.otlp` forwards to Grafana Cloud Tempo. |
| **Logs** | `discovery.kubernetes` finds pods in the namespaces listed under `podDiscovery.namespaces`. `loki.source.kubernetes` tails their container stdout via the kubelet API. `loki.write` pushes to Grafana Cloud Loki. |

## Install

```bash
# Depends on ESO + a ClusterSecretStore named "onepassword" already existing
# in the cluster (installed by the tuist chart's prerequisites).
helm upgrade --install alloy infra/helm/alloy \
  -n observability --create-namespace
```

Required 1Password items in the vault referenced by the ClusterSecretStore:

| Item name | Category | Field used |
|---|---|---|
| `PROMETHEUS_TOKEN` | Password | `password` |
| `LOKI_TOKEN` | Password | `password` |
| `TEMPO_TOKEN` | Password | `password` |

Non-secret values (URLs, numeric usernames) are baked into `values.yaml` — verify they match your Grafana Cloud stack before first install.

## RBAC — what access does Alloy get?

The `loki.source.kubernetes` component streams pod container logs via the Kubernetes API server's kubelet proxy. That needs:

- `get/list/watch` on `pods` (cluster-wide, for pod discovery)
- `get/list/watch` on `pods/log` (to read container stdout)
- `get/list/watch` on `nodes/proxy` (the kubelet proxy endpoint)
- `get/list/watch` on `nodes/metrics` (kubelet metrics endpoint, used by discovery)

This is **cluster-scoped kubelet API access**. Practical implication: a compromised Alloy pod could read stdout of any pod in any namespace in the cluster. Scope is limited to `namespaces` listed under `podDiscovery.namespaces` at the *discovery* layer, but RBAC itself is cluster-wide.

Mitigations we already have in place:

- Alloy's image is pinned (`v1.11.0`) and small, reducing attack surface
- Grafana Cloud tokens live in 1Password, not mounted as files
- Log forwarding is outbound-only (no listeners except the OTLP/Loki push ports the server reaches via ClusterIP)

If stronger isolation becomes necessary later, options are:
1. Run Alloy as a DaemonSet with `hostPath` access to `/var/log/pods/` (reads only the local node's logs — narrower blast radius, different RBAC).
2. Split into per-namespace Alloy instances with `Role` instead of `ClusterRole`.

## Local validation

```bash
helm lint infra/helm/alloy
helm template alloy infra/helm/alloy | kubectl apply --dry-run=client -f -
```

## Verify it's working

```bash
# Spans received from the server (should increment over time)
kubectl -n observability port-forward svc/alloy-tuist-alloy 12345:12345 &
curl -s http://localhost:12345/metrics | grep otelcol_receiver_accepted_spans_total

# Loki push successes (HTTP 204 count)
curl -s http://localhost:12345/metrics | grep loki_source_api_request_duration_seconds_count
```

In Grafana Cloud: pick the stack, filter by labels `service_name=tuist-server` (metrics/traces), `env=staging` (logs).
