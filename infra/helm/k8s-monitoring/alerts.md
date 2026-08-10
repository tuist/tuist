# Control plane and stable egress alerts

The monitoring chart sends the signals needed to distinguish a Kubernetes
control-endpoint interruption from an etcd stall, a Hetzner load-balancer
failure, or a stable outbound-gateway failure.

All queries below are suitable for Grafana-managed alert rules. Use the
Grafana Cloud metrics data source and evaluate them every minute.

The metrics `cluster` label uses `tuist-production`, `tuist-staging`,
`tuist-canary`, and `tuist-management`. The Cluster API
`workload_cluster` label uses the Kubernetes Cluster object names `tuist`,
`tuist-staging`, and `tuist-canary`, so production deliberately differs
between these two labels.

## Critical alerts

### Kubernetes control endpoint unavailable

```promql
min by (cluster, instance) (
  min_over_time(up{job="tuist-kube-apiserver"}[2m])
) == 0
```

- Pending period: 0 minutes
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

### Kubernetes control-plane scrape telemetry missing

```promql
absent_over_time(up{cluster="tuist-production", job="tuist-kube-apiserver"}[5m])
or
absent_over_time(up{cluster="tuist-production", job="tuist-etcd"}[5m])
or
absent_over_time(up{cluster="tuist-staging", job="tuist-kube-apiserver"}[5m])
or
absent_over_time(up{cluster="tuist-staging", job="tuist-etcd"}[5m])
or
absent_over_time(up{cluster="tuist-canary", job="tuist-kube-apiserver"}[5m])
or
absent_over_time(up{cluster="tuist-canary", job="tuist-etcd"}[5m])
or
absent_over_time(up{cluster="tuist-management", job="tuist-kube-apiserver"}[5m])
or
absent_over_time(up{cluster="tuist-management", job="tuist-etcd"}[5m])
```

- Pending period: 0 minutes
- Summary: `Kubernetes control-plane scrape telemetry is missing for {{ $labels.job }} in {{ $labels.cluster }}`

### Kubernetes requests terminated

```promql
sum by (cluster) (
  increase(apiserver_request_terminations_total[2m])
) > 0
```

- Pending period: 0 minutes
- Summary: `Kubernetes control endpoint terminated requests in {{ $labels.cluster }}`

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
  min_over_time(up{job="tuist-etcd"}[2m])
) == 0
```

- Pending period: 0 minutes
- Summary: `etcd metrics unavailable on {{ $labels.instance }} ({{ $labels.cluster }})`

### Hetzner control-plane load-balancer target unhealthy

```promql
min by (
  cluster,
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
- Summary: `Hetzner load balancer {{ $labels.hetzner_load_balancer_name }} has an unhealthy control-plane target ({{ $labels.cluster }})`

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

### Control-plane replica telemetry missing

```promql
absent_over_time(
  kube_customresource_kubeadmcontrolplane_spec_replicas{
    cluster="tuist-management"
  }[10m]
)
```

- Pending period: 0 minutes
- Summary: `Control-plane desired and ready replica telemetry is missing`

### Orphan Hetzner servers

Servers with no owning CAPI `Machine`, from the `reconciliation-checks`
CronJob (`infra/k8s/mgmt/reconciliation-checks.yaml`).

```promql
max by (cluster) (
  capi_reconciliation_orphan_servers{cluster="tuist-management"}
) > 0
```

- Pending period: 15 minutes
- Summary: `{{ $value }} Hetzner server(s) have no owning CAPI Machine`

### Cluster removed from git still live

Live `Cluster` objects absent from git — the never-prune blind spot the
Hetzner orphan check misses (their servers still have valid `Machine` owners).

```promql
max by (cluster) (
  capi_reconciliation_stale_clusters{cluster="tuist-management"}
) > 0
```

- Pending period: 15 minutes
- Summary: `{{ $value }} live Cluster(s) are absent from git (stale)`

### Reconciliation-check telemetry missing

```promql
absent_over_time(
  capi_reconciliation_orphan_servers{cluster="tuist-management"}[30m]
)
```

- Pending period: 0 minutes
- Summary: `Orphan-server / stale-cluster reconciliation telemetry is missing (CronJob or Pushgateway down)`

### Cluster API admission webhook failing (fleet-wide write freeze)

The management cluster serves the CAPI/CAPH admission webhooks with a
cert-manager certificate. If it expires — or the controllers keep serving a
stale one after cert-manager renews it, which is what happened on 2026-07-30 —
the API server can no longer call the webhooks, and because they are
`failurePolicy: Fail` every write to a `cluster.x-k8s.io` object is rejected
across all workload clusters. Node replacement and autoscaling freeze
fleet-wide (production included; it was spared last time only because nothing
needed replacing). This is the root-cause detector; nothing else here catches
it directly. The rejections surface as `calling_webhook_error` on the mgmt
API server.

```promql
sum by (name) (
  rate(
    apiserver_admission_webhook_rejection_count{
      cluster="tuist-management",
      error_type="calling_webhook_error",
      name=~".+\.cluster\.x-k8s\.io"
    }[5m]
  )
) > 0
```

- Pending period: 5 minutes
- Summary: `Cluster API admission webhook {{ $labels.name }} is failing on the management cluster — cluster.x-k8s.io writes are frozen fleet-wide`

### Worker node pool below desired replicas

Catches a worker MachineDeployment (the stable-egress gateway pool, or a
production processor/kura pool) running with fewer ready nodes than desired —
for example when MachineHealthCheck deleted nodes that CAPI then could not
recreate. Independent of the stable-egress-gateway signal, so it also covers
non-egress pools. Both series are exported by the management cluster's
kube-state-metrics CustomResourceState.

```promql
kube_customresource_machinedeployment_ready_replicas{
  cluster="tuist-management"
}
<
kube_customresource_machinedeployment_spec_replicas{
  cluster="tuist-management"
}
```

- Pending period: 15 minutes
- Summary: `Worker pool {{ $labels.machinedeployment }} ({{ $labels.workload_cluster }}) has fewer ready nodes than desired`

### Worker node pool telemetry missing

```promql
absent_over_time(
  kube_customresource_machinedeployment_spec_replicas{
    cluster="tuist-management"
  }[15m]
)
```

- Pending period: 0 minutes
- Summary: `Worker MachineDeployment replica telemetry is missing on the management cluster`

### Node exporter coverage incomplete

```promql
count by (cluster) (
  up{job="integrations/node_exporter"} == 1
)
<
max by (cluster) (
  kube_daemonset_status_desired_number_scheduled{
    namespace="observability",
    daemonset="k8s-monitoring-node-exporter"
  }
)
```

- Pending period: 5 minutes
- Summary: `Node-level host metrics are missing for one or more nodes in {{ $labels.cluster }}`

### Node exporter telemetry missing

```promql
absent_over_time(
  up{cluster="tuist-production", job="integrations/node_exporter"}[10m]
)
or
absent_over_time(
  up{cluster="tuist-staging", job="integrations/node_exporter"}[10m]
)
or
absent_over_time(
  up{cluster="tuist-canary", job="integrations/node_exporter"}[10m]
)
or
absent_over_time(
  up{cluster="tuist-management", job="integrations/node_exporter"}[10m]
)
```

- Pending period: 0 minutes
- Summary: `Node exporter telemetry is missing in {{ $labels.cluster }}`

### Stable outbound gateway unavailable

```promql
max by (cluster) (
  tuist_stable_egress_gateway_available
) == 0
```

- Pending period: 2 minutes
- Summary: `No healthy prepared stable outbound gateway in {{ $labels.cluster }}`

### Stable outbound gateway telemetry missing

```promql
absent_over_time(
  tuist_stable_egress_gateway_available{cluster="tuist-production"}[10m]
)
or
absent_over_time(
  tuist_stable_egress_gateway_available{cluster="tuist-staging"}[10m]
)
or
absent_over_time(
  tuist_stable_egress_gateway_available{cluster="tuist-canary"}[10m]
)
```

- Pending period: 0 minutes
- Summary: `Stable outbound gateway telemetry is missing in {{ $labels.cluster }}`

### Stable outbound traffic dropped

```promql
sum by (cluster) (
  rate(cilium_drop_count_total{
    direction="INGRESS",
    reason="No Egress IP configured"
  }[5m])
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

### Tuist license invalid or near expiration

```promql
min by (cluster, namespace) (
  tuist_license_valid
) == 0
or
(
  min by (cluster, namespace) (
    tuist_license_expiration_timestamp_seconds
  )
  - time()
) < 604800
```

- Pending period: 0 minutes
- Summary: `Tuist license is invalid or expires within seven days in {{ $labels.cluster }}`

### Tuist license telemetry missing

```promql
absent_over_time(
  tuist_license_valid{cluster="tuist-production"}[15m]
)
or
absent_over_time(
  tuist_license_valid{cluster="tuist-staging"}[15m]
)
or
absent_over_time(
  tuist_license_valid{cluster="tuist-canary"}[15m]
)
```

- Pending period: 0 minutes
- Summary: `Tuist license telemetry is missing in {{ $labels.cluster }}`

### Public endpoint unavailable from multiple locations

Create a Grafana Synthetic Monitoring Hypertext Transfer Protocol check named
`tuist-public-readiness` for `https://tuist.dev`, run it every minute from at
least three public probes, and set its **Job** field to
`tuist-public-readiness`. Alert when fewer than two probes have succeeded in
the last three minutes:

```promql
sum(
  max by (probe) (
    max_over_time(
      probe_success{job="tuist-public-readiness"}[3m]
    )
  )
) < 2
```

- Pending period: 0 minutes
- Summary: `Tuist is unavailable from multiple external probe locations`

### Public endpoint telemetry missing

```promql
absent_over_time(
  probe_success{job="tuist-public-readiness"}[3m]
)
```

- Pending period: 0 minutes
- Summary: `The public endpoint check stopped producing telemetry`

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

### Kubernetes priority level concurrency saturated

```promql
sum by (cluster, instance, priority_level) (
  apiserver_flowcontrol_current_executing_seats
)
/
clamp_min(
  max by (cluster, instance, priority_level) (
    apiserver_flowcontrol_current_limit_seats
  ),
  1
) > 0.8
```

- Pending period: 5 minutes
- Summary: `Kubernetes priority level {{ $labels.priority_level }} uses more than 80% of its request capacity in {{ $labels.cluster }}`

### Kubernetes server errors

```promql
(
  sum by (cluster) (
    rate(apiserver_request_total{code=~"5.."}[5m])
  )
  /
  clamp_min(
    sum by (cluster) (
      rate(apiserver_request_total[5m])
    ),
    1
  )
) > 0.01
and
sum by (cluster) (
  rate(apiserver_request_total{code=~"5.."}[5m])
) > 0.1
```

- Pending period: 5 minutes
- Summary: `More than 1% of Kubernetes requests are server errors in {{ $labels.cluster }}`

### Kubernetes rate limiting responses

```promql
sum by (cluster) (
  rate(apiserver_request_total{code="429"}[5m])
) > 0.1
```

- Pending period: 5 minutes
- Summary: `Kubernetes is rate limiting requests in {{ $labels.cluster }}`

### Ingress server-error response ratio

```promql
(
  sum by (cluster, namespace, ingress) (
    rate(nginx_ingress_controller_requests{status=~"5.."}[5m])
  )
  /
  clamp_min(
    sum by (cluster, namespace, ingress) (
      rate(nginx_ingress_controller_requests[5m])
    ),
    1
  )
) > 0.01
and
sum by (cluster, namespace, ingress) (
  rate(nginx_ingress_controller_requests{status=~"5.."}[5m])
) > 0.1
```

- Pending period: 2 minutes
- Summary: `More than 1% of ingress requests are server errors for {{ $labels.ingress }} in {{ $labels.cluster }}`

### Tuist server request read timeouts

```promql
sum by (cluster, namespace, method, route) (
  increase(tuist_http_request_timeout_count[5m])
) > 5
```

- Pending period: 2 minutes
- Summary: `Bandit reported repeated request read timeouts for {{ $labels.route }} in {{ $labels.cluster }}`

### Tuist license expires within 30 days

```promql
(
  min by (cluster, namespace) (
    tuist_license_expiration_timestamp_seconds
  )
  - time()
) < 2592000
and
min by (cluster, namespace) (
  tuist_license_valid
) == 1
```

- Pending period: 1 hour
- Summary: `Tuist license expires within 30 days in {{ $labels.cluster }}`

### Database connection pool starved

```promql
sum by (cluster, namespace, repo, database) (
  increase(tuist_repo_pool_checkout_queue_starved_samples_sum[5m])
)
/
clamp_min(
  sum by (cluster, namespace, repo, database) (
    increase(tuist_repo_pool_checkout_queue_total_samples_sum[5m])
  ),
  1
) > 0.1
```

- Pending period: 2 minutes
- Summary: `More than 10% of database pool samples had queued work and no ready connection for {{ $labels.repo }} in {{ $labels.cluster }}`

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

### etcd peer round-trip latency

```promql
histogram_quantile(
  0.99,
  sum by (cluster, instance, le) (
    rate(etcd_network_peer_round_trip_time_seconds_bucket[5m])
  )
) > 0.1
```

- Pending period: 5 minutes
- Summary: `etcd peer round-trip latency is above 100 milliseconds on {{ $labels.instance }}`

### etcd leader changed

```promql
sum by (cluster) (
  increase(etcd_server_leader_changes_seen_total[10m])
) > 0
```

- Pending period: 0 minutes
- Summary: `etcd leadership changed in {{ $labels.cluster }}`

### etcd proposals stalled or failed

```promql
max by (cluster, instance) (
  etcd_server_proposals_pending
) > 100
or
sum by (cluster, instance) (
  increase(etcd_server_proposals_failed_total[5m])
) > 0
```

- Pending period: 2 minutes
- Summary: `etcd proposals are stalled or failing on {{ $labels.instance }}`

### etcd slow applies

```promql
sum by (cluster, instance) (
  increase(etcd_server_slow_apply_total[5m])
) > 0
```

- Pending period: 0 minutes
- Summary: `etcd reported slow request application on {{ $labels.instance }}`

### Control-plane process file descriptors nearly exhausted

```promql
max by (cluster, job, instance) (
  process_open_fds{
    job=~"tuist-kube-apiserver|tuist-etcd"
  }
  /
  clamp_min(
    process_max_fds{
      job=~"tuist-kube-apiserver|tuist-etcd"
    },
    1
  )
) > 0.8
```

- Pending period: 5 minutes
- Summary: `{{ $labels.job }} uses more than 80% of its file descriptor limit on {{ $labels.instance }}`

### Host processor saturation

```promql
1 - avg by (cluster, instance) (
  rate(node_cpu_seconds_total{mode="idle"}[5m])
) > 0.9
```

- Pending period: 10 minutes
- Summary: `Host processor utilization is above 90% on {{ $labels.instance }}`

### Host processor steal time

```promql
avg by (cluster, instance) (
  rate(node_cpu_seconds_total{mode="steal"}[5m])
) > 0.1
```

- Pending period: 5 minutes
- Summary: `Virtual machine host contention is stealing processor time from {{ $labels.instance }}`

### Host disk input/output saturation

```promql
max by (cluster, instance) (
  rate(node_disk_io_time_seconds_total{
    device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
  }[5m])
) > 0.8
```

- Pending period: 10 minutes
- Summary: `Host disk is busy more than 80% of the time on {{ $labels.instance }}`

### Host disk operation latency

```promql
max by (cluster, instance) (
  (
    rate(node_disk_read_time_seconds_total{
      device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
    }[5m])
    +
    rate(node_disk_write_time_seconds_total{
      device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
    }[5m])
  )
  /
  clamp_min(
    rate(node_disk_reads_completed_total{
      device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
    }[5m])
    +
    rate(node_disk_writes_completed_total{
      device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
    }[5m]),
    0.001
  )
) > 0.05
and
max by (cluster, instance) (
  rate(node_disk_reads_completed_total{
    device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
  }[5m])
  +
  rate(node_disk_writes_completed_total{
    device=~"(sd|vd|xvd)[a-z]+|nvme[0-9]+n[0-9]+"
  }[5m])
) > 1
```

- Pending period: 5 minutes
- Summary: `Host disk operations average more than 50 milliseconds on {{ $labels.instance }}`

### Host network errors

```promql
sum by (cluster, instance) (
  rate({
    __name__=~"node_network_(receive|transmit)_errs_total",
    device=~"e(n|th).*"
  }[5m])
) > 0
```

- Pending period: 5 minutes
- Summary: `Host network interface reports errors on {{ $labels.instance }}`

### Host network packet drops

```promql
(
  sum by (cluster, instance) (
    rate({
      __name__=~"node_network_(receive|transmit)_drop_total",
      device=~"e(n|th).*"
    }[5m])
  )
  /
  clamp_min(
    sum by (cluster, instance) (
      rate({
        __name__=~"node_network_(receive|transmit)_packets_total",
        device=~"e(n|th).*"
      }[5m])
    ),
    1
  )
) > 0.001
and
sum by (cluster, instance) (
  rate({
    __name__=~"node_network_(receive|transmit)_packets_total",
    device=~"e(n|th).*"
  }[5m])
) > 100
```

- Pending period: 5 minutes
- Summary: `Host network packet drops exceed 0.1% on {{ $labels.instance }}`

### Host clock offset

```promql
max by (cluster, instance) (
  abs(node_timex_offset_seconds)
) > 0.1
```

- Pending period: 5 minutes
- Summary: `Host clock differs from its time source by more than 100 milliseconds on {{ $labels.instance }}`

### Transmission Control Protocol retransmissions

```promql
sum by (cluster, instance) (
  rate(node_netstat_Tcp_RetransSegs[5m])
)
/
clamp_min(
  sum by (cluster, instance) (
    rate(node_netstat_Tcp_OutSegs[5m])
  ),
  1
) > 0.01
```

- Pending period: 5 minutes
- Summary: `Transmission Control Protocol retransmissions exceed 1% on {{ $labels.instance }}`

### Stable outbound gateway not prepared

```promql
min by (cluster, node) (
  tuist_stable_egress_gateway_prepared
) == 0
```

- Pending period: 5 minutes
- Summary: `Stable outbound gateway candidate {{ $labels.node }} is not prepared`

### Stable outbound gateway redundancy lost

```promql
sum by (cluster) (
  max by (cluster, node) (
    tuist_stable_egress_gateway_prepared
  )
) < 2
```

- Pending period: 5 minutes
- Summary: `Fewer than two stable outbound gateway candidates are prepared in {{ $labels.cluster }}`

### Stable outbound gateway direct health check failing

```promql
min by (cluster, node) (
  tuist_stable_egress_gateway_node_healthy
) == 0
```

- Pending period: 2 minutes
- Summary: `Cilium is not directly reachable on stable outbound gateway {{ $labels.node }}`

### Stable outbound gateway failed over

```promql
sum by (cluster) (
  increase(tuist_stable_egress_failovers_total[10m])
) > 0
```

- Pending period: 0 minutes
- Summary: `The stable outbound address moved to another gateway in {{ $labels.cluster }}`

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

Kubernetes API server and etcd process pressure:

```promql
rate(process_cpu_seconds_total{job=~"tuist-kube-apiserver|tuist-etcd"}[5m])
```

```promql
process_resident_memory_bytes{job=~"tuist-kube-apiserver|tuist-etcd"}
```

```promql
process_open_fds{job=~"tuist-kube-apiserver|tuist-etcd"}
/
clamp_min(
  process_max_fds{job=~"tuist-kube-apiserver|tuist-etcd"},
  1
)
```

```promql
histogram_quantile(
  0.99,
  sum by (cluster, job, instance, le) (
    rate(go_sched_latencies_seconds_bucket{
      job="tuist-kube-apiserver"
    }[5m])
  )
)
```

Server database pool pressure:

```promql
max by (cluster, namespace, repo, database) (
  tuist_repo_pool_checkout_queue_length
)
```

```promql
min by (cluster, namespace, repo, database) (
  tuist_repo_pool_ready_conn_count
)
```

## Create the rules in Grafana

1. Open **Alerts & incident response → Alerting → Alert rules**.
2. Select **New alert rule**.
3. Choose the Grafana Cloud metrics data source.
4. Paste one query from this document and set it as the alert condition.
5. Set the evaluation interval to one minute and use the pending period shown
   with the query.
6. Set **No Data** to **Normal** for threshold rules. Healthy comparison
   expressions commonly return an empty result, and treating that as alerting
   creates false positives.
7. Use the explicit telemetry-missing rules in this document to detect absent
   series. They use `absent_over_time` and fire even though threshold rules use
   **No Data: Normal**.
8. Set **Error** to **Alerting** for the critical availability and
   telemetry-missing rules. Use **Keep Last State** for capacity and latency
   warnings so a data-source evaluation error does not fan out into unrelated
   warnings.
9. Add the suggested summary, a `severity` label, and the notification contact
   point used by the infrastructure team.
10. Preview the raw metric selector and the final comparison separately against
    recent data before saving it.

The same rules can be created with Grafana Assistant. Give it this prompt:

```text
Create Grafana-managed alert rules from
infra/helm/k8s-monitoring/alerts.md. Use the Grafana Cloud metrics data source,
preserve every query and pending period exactly, put the rules in a folder
named Tuist infrastructure, add the suggested summary as the annotation, and
route critical and warning severities through our existing infrastructure
notification policy. Configure No Data and Error as Alerting for every
explicit telemetry-missing rule. Configure No Data as Normal for every
threshold rule. Configure Error as Alerting for critical availability and
telemetry-missing rules, and Keep Last State for warning rules. Group
notifications by cluster and alert name. Preview each raw metric selector and
final comparison against the last seven days, report any selector with no
matching series, and show me the resulting rules before saving.
```
