# Control plane and stable egress alerts

The monitoring chart sends the signals needed to distinguish a Kubernetes
control-endpoint interruption from an etcd stall, a Hetzner load-balancer
failure, or a stable outbound-gateway failure.

All queries below are suitable for Grafana-managed alert rules. Use the
Grafana Cloud metrics data source and evaluate them every minute.

## Critical alerts

### Kubernetes control endpoint unavailable

```promql
min by (cluster, instance) (
  up{job="tuist-kube-apiserver"}
) == 0
```

- Pending period: 2 minutes
- Summary: `Kubernetes control endpoint unavailable on {{ $labels.instance }} ({{ $labels.cluster }})`

### Kubernetes control-plane collector unavailable

```promql
kube_daemonset_status_number_unavailable{
  namespace="observability",
  daemonset="k8s-monitoring-alloy-control-plane"
} > 0
```

- Pending period: 2 minutes
- Summary: `Control-plane metrics collector unavailable in {{ $labels.cluster }}`

### Kubernetes requests rejected

```promql
sum by (cluster) (
  increase(apiserver_flowcontrol_rejected_requests_total[5m])
) > 0
```

- Pending period: 2 minutes
- Summary: `Kubernetes control endpoint is rejecting requests in {{ $labels.cluster }}`

### etcd has no leader

```promql
min by (cluster, instance) (
  etcd_server_has_leader
) == 0
```

- Pending period: 2 minutes
- Summary: `etcd has no leader on {{ $labels.instance }} ({{ $labels.cluster }})`

### etcd scrape unavailable

```promql
min by (cluster, instance) (
  up{job="tuist-etcd"}
) == 0
```

- Pending period: 2 minutes
- Summary: `etcd metrics unavailable on {{ $labels.instance }} ({{ $labels.cluster }})`

### Hetzner control-plane load-balancer target unhealthy

```promql
min by (
  hetzner_load_balancer_name,
  hetzner_target_name,
  hetzner_target_port
) (
  hetzner_load_balancer_service_state{
    cluster="tuist-management",
    hetzner_load_balancer_name=~"tuist(|-staging|-canary)-.*-kube-apiserver-.*"
  }
) == 0
```

- Pending period: 2 minutes
- Summary: `Hetzner load balancer {{ $labels.hetzner_load_balancer_name }} has an unhealthy control-plane target`

### Hetzner load-balancer exporter unavailable

```promql
kube_deployment_status_replicas_available{
  cluster="tuist-management",
  namespace="org-tuist",
  deployment="hcloud-load-balancer-exporter"
}
<
kube_deployment_spec_replicas{
  cluster="tuist-management",
  namespace="org-tuist",
  deployment="hcloud-load-balancer-exporter"
}
```

- Pending period: 2 minutes
- Summary: `Hetzner load-balancer telemetry exporter is unavailable`

### Hetzner load-balancer telemetry missing

```promql
absent_over_time(
  hetzner_load_balancer_service_state{
    cluster="tuist-management",
    hetzner_load_balancer_name=~"tuist(|-staging|-canary)-.*-kube-apiserver-.*"
  }[5m]
)
```

- Pending period: 0 minutes
- Summary: `Hetzner control-plane load-balancer health telemetry is missing`

### Control-plane replicas below desired state

```promql
kube_customresource_kubeadmcontrolplane_ready_replicas{
  cluster="tuist-management",
  workload_cluster=~"tuist|tuist-staging|tuist-canary"
}
<
kube_customresource_kubeadmcontrolplane_spec_replicas{
  cluster="tuist-management",
  workload_cluster=~"tuist|tuist-staging|tuist-canary"
}
```

- Pending period: 10 minutes
- Summary: `Control plane for {{ $labels.workload_cluster }} has fewer ready replicas than desired`

### Stable outbound gateway unavailable

```promql
max by (cluster) (
  tuist_stable_egress_gateway_available
) == 0
```

- Pending period: 2 minutes
- Summary: `No healthy prepared stable outbound gateway in {{ $labels.cluster }}`

### Stable outbound traffic dropped

```promql
sum by (cluster) (
  rate(cilium_drop_count_total{reason="No Egress IP configured"}[5m])
) > 0
```

- Pending period: 2 minutes
- Summary: `Cilium is dropping stable outbound traffic in {{ $labels.cluster }}`

### Tuist server replicas unavailable

```promql
kube_deployment_status_replicas_available{
  namespace=~"tuist|tuist-staging|tuist-canary",
  deployment="tuist-tuist-server"
}
<
kube_deployment_spec_replicas{
  namespace=~"tuist|tuist-staging|tuist-canary",
  deployment="tuist-tuist-server"
}
```

- Pending period: 2 minutes
- Summary: `Tuist server has unavailable replicas in {{ $labels.namespace }}`

## Warning alerts

### Kubernetes request latency

```promql
histogram_quantile(
  0.99,
  sum by (cluster, le) (
    rate(apiserver_request_duration_seconds_bucket{
      verb!~"WATCH|CONNECT"
    }[5m])
  )
) > 1
```

- Pending period: 5 minutes
- Summary: `Kubernetes request latency above one second in {{ $labels.cluster }}`

### etcd write-ahead-log synchronization latency

```promql
histogram_quantile(
  0.99,
  sum by (cluster, instance, le) (
    rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])
  )
) > 0.5
```

- Pending period: 5 minutes
- Summary: `etcd write-ahead-log synchronization is slow on {{ $labels.instance }}`

### etcd backend commit latency

```promql
histogram_quantile(
  0.99,
  sum by (cluster, instance, le) (
    rate(etcd_disk_backend_commit_duration_seconds_bucket[5m])
  )
) > 0.25
```

- Pending period: 5 minutes
- Summary: `etcd backend commits are slow on {{ $labels.instance }}`

### Stable outbound gateway not prepared

```promql
min by (cluster, node) (
  tuist_stable_egress_gateway_prepared
) == 0
```

- Pending period: 5 minutes
- Summary: `Stable outbound gateway candidate {{ $labels.node }} is not prepared`

### Stable outbound controller reconciliation errors

```promql
sum by (cluster) (
  increase(controller_runtime_reconcile_errors_total{
    controller="stable-egress-failover"
  }[5m])
) > 0
```

- Pending period: 2 minutes
- Summary: `Stable outbound controller reconciliation is failing in {{ $labels.cluster }}`

## Useful investigation queries

Current Kubernetes requests in flight:

```promql
sum by (cluster, request_kind) (
  apiserver_current_inflight_requests
)
```

Hetzner load-balancer connections and traffic:

```promql
hetzner_load_balancer_open_connections{cluster="tuist-management"}
```

```promql
hetzner_load_balancer_bandwidth_in{cluster="tuist-management"}
```

```promql
hetzner_load_balancer_bandwidth_out{cluster="tuist-management"}
```

Stable outbound gateway assignments:

```promql
tuist_stable_egress_gateway_active
```

## Create the rules in Grafana

1. Open **Alerts & incident response → Alerting → Alert rules**.
2. Select **New alert rule**.
3. Choose the Grafana Cloud metrics data source.
4. Paste one query from this document and set it as the alert condition.
5. Set the evaluation interval to one minute and use the pending period shown
   with the query.
6. For availability rules, set the **No Data** state to **Alerting** so a
   missing collector or exporter cannot turn an outage into a silent query.
7. Add the suggested summary, a `severity` label, and the notification contact
   point used by the infrastructure team.
8. Preview the rule against recent data before saving it.

The same rules can be created with Grafana Assistant. Give it this prompt:

> Create Grafana-managed alert rules from
> `infra/helm/k8s-monitoring/alerts.md`. Use the Grafana Cloud metrics data
> source, preserve every query and pending period exactly, put the rules in a
> folder named `Tuist infrastructure`, add the suggested summary as the
> annotation, and route critical and warning severities through our existing
> infrastructure notification policy. Configure No Data as Alerting for every
> availability rule. Preview each query and show me the resulting rules before
> saving.
