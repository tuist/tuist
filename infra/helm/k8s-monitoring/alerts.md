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

Metrics scraped over the tailnet (`tuist-macos-node-exporter`,
`tuist-macos-tart-kubelet`, `tuist-macos-pod-metrics`) come from
`collectors.alloy-metrics.extraConfig`, which sits outside the chart's
`declare` blocks and forwards straight to the Grafana Cloud destination.
They therefore carry the destination's external labels (`cluster`,
`env`) but not any label a chart feature adds inside its own pipeline.
Group those rules by `cluster` and `env` together, and confirm both
labels are present in Explore before saving a rule that relies on one to
separate environments.

## Routing to Grafana IRM

Every rule below routes through Grafana IRM, which is also what the
public status page reads: `status/` republishes the Grafana Incident API
and derives its component list from the IRM label field named by
`GRAFANA_COMPONENT_LABEL_KEY` (default `affected_service`). See
[`status/AGENTS.md`](../../../status/AGENTS.md).

Two consequences when creating a rule:

- Give it a `severity` label (`critical` or `warning`) so the existing
  notification policy routes it. Critical maps to a page; warning maps
  to the Slack receiver only.
- Give customer-visible rules an `affected_service` label whose value
  matches an existing select option on that IRM label field. Without it
  an incident opened from the alert rolls up to no component and the
  status page keeps showing the service as operational during an
  outage. The remote-processing rules in this document are
  customer-visible: a stalled `:process_xcresult` queue means test runs
  sit unprocessed for every account using remote processing.

If the option does not exist yet, add it in Grafana Cloud → IRM →
Settings → Labels first; the worker matches on the option's `value`, and
an unmatched label value is silently ignored.

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

### Kura cache rejecting runner traffic

```promql
sum by (cluster, node) (
  rate(cilium_drop_count_total{
    direction="INGRESS",
    reason="Policy denied"
  }[5m])
  * on (cluster, pod) group_left(node)
  kube_pod_info{
    namespace="kube-system",
    pod=~"cilium-.*",
    node=~".*-kura-fleet-.*"
  }
) > 0
```

- Pending period: 10 minutes
- Severity: critical
- Already created: rule `ffuscyncueo74d`, folder `Alerts`, group `Runners`,
  receiver `Slack #notifications 2` — alongside the other runner-host alerts,
  since the actionable target is a Mac mini even though the signal is measured
  at the cache.
- The metric carries no `node` label, hence the `kube_pod_info` join on the
  Cilium agent pod. The `node=~".*-kura-fleet-.*"` matcher restricts this to the
  co-located runner-cache nodes; other pools carry far heavier background policy
  drops (one dedibox node holds a flat ~0.42/s indefinitely) and would swamp it.
- Summary: `Kura cache on {{ $labels.node }} is dropping runner traffic at the
  NetworkPolicy ({{ $labels.cluster }}) — builds on the affected runner will
  hang until their client timeouts`
- Blind spot, covered by the next rule: this detects VM traffic *arriving*
  mis-sourced. A host with no PN VLAN at all has no PN route, so its cache
  traffic never reaches the kura node and this counter stays at zero while the
  build hangs identically.

**The window is `[5m]`, not `[10m]`. The threshold stays `> 0` deliberately.**

The rule is meant to catch *any* sustained denial, so a magnitude floor was
rejected: it would have to be tuned, and it would silently hide a low-rate variant
of the same fault. The discrimination belongs on duration instead, which is what
the pending period already expresses. `[10m]` broke that: a rate over a 10-minute
window stays non-zero for a full 10 minutes after the *last* dropped packet, so a
4-minute burst held the condition for ~14 minutes and cleared a 10-minute pending
period. Any burst of roughly a minute could page. With `[5m]` the same burst holds
the condition for about 7 minutes and never reaches the pending period, while a
genuinely stuck job, which drips for hours, still fires after 10 minutes exactly as
before. The pending period now means "still dropping" rather than "dropped
recently".

That matters because these nodes do **not** sit at exactly zero, contrary to what
an earlier version of this note claimed. Two distinct populations show up:

- **Transient bursts, 0.02 to 0.10 packets/s, a few minutes long.** A
  **kura-controller rollout** produces one on *all four* kura-hosting nodes at
  once, within seconds of the new ReplicaSet appearing, on roughly half of
  rollouts. Since every merge to `main` rolls the controller, a rule that pages on
  these pages constantly. The `[5m]` window is what suppresses them. The mechanism
  is not yet proven, but the obvious suspects are ruled out: the policy object is
  patched, never recreated (`reconcileNetworkPolicy` uses
  `controllerutil.CreateOrUpdate`, and the live objects are still `generation: 1`),
  no Cilium agent restarts, and a rolling update reuses the same pod labels so no
  new security identity has to propagate. Cilium runs `routing-mode: tunnel`, which
  carries the source identity in the VXLAN header, so ordinary in-cluster
  pod-to-pod traffic is matched by `namespaceSelector: {}` and allowed. That leaves
  a path where the pod identity is *lost*: from outside the cluster, or SNATed
  through a NodePort/LoadBalancer. Note the `peer` rule already had to open
  `0.0.0.0/0` for exactly that reason, while `http` has no equivalent escape hatch
  beyond per-instance `ClientCIDRs`.
- **Sustained episodes, 0.8 to 5 packets/s, lasting 30 minutes to 6 hours.** These
  are the real thing and the rule *should* page on them. Treat a firing alert as a
  genuine mis-sourced host, not as noise. The impact is now measured rather than
  assumed: across 2026-08-10 to 2026-08-14 the production node had 20 such
  episodes, and **every one of the 17 macOS runner sessions that exceeded 40
  minutes in that window started inside one of them**, 17 for 17. Outside those
  episodes not a single macOS session passed 40 minutes (max 30.2 min over 650
  sessions). Linux pools show no effect either way, which is the control: they do
  not use the PN/pf NAT path. Three sessions hit exactly 361 minutes, the 6-hour
  ceiling. Total burned wall-clock was ~34 hours across two accounts.

  Those episodes stopped on 2026-08-14 once `b4ce0dba49` fixed the duplicated
  `/etc/pf.conf` anchor block that made `pfctl` reject the whole ruleset (see
  "Runner host PN VLAN missing" below for the companion failure). In the three days
  after, 255 macOS sessions ran with **zero** over 40 minutes and a 27-minute max,
  and the node logged no sustained episode at all. If this class reappears, the pf
  anchor is the first thing to check.

Before concluding a Mac mini is mis-sourced, check that the drops are confined to
**one** node. A runner VM talks to a single regional cache, so simultaneous drops
across regions are never a mis-sourced host.

A per-instance kura NetworkPolicy admits `http` only from `namespaceSelector: {}`
and `ipBlock 172.16.0.0/22` (the Private Network). A macOS runner VM whose egress
is not masqueraded to its host's PN VLAN address arrives from outside that block,
so Cilium drops it at ingress — silently, with no RST. The client sees no
connection at all and every cache request hangs until its own timeout, which has
turned 8-minute CI jobs into 6-hour ones while every dashboard showed kura
healthy and idle. The drop counter is the only signal that fires, and it tracks
the stuck job closely: a steady ~1-2/s SYN-retransmit trickle for its whole life,
falling back to baseline within a scrape of it being cancelled. What makes it
detectable is that it *persists*, which is why the rule discriminates on duration
rather than on magnitude.

Note `cilium_drop_count_total` carries no source address, so on its own it says
*that* a host is mis-sourced but not *which* one. Use `hubble_drop_total`, which
carries `source` and `destination`:

```promql
topk(10, sum by (source, destination) (
  rate(hubble_drop_total{reason="POLICY_DENIED", protocol="TCP"}[5m])
))
```

An in-cluster source resolves to a pod name; a mis-sourced runner VM or a SNATed
path resolves to a bare IP, which is the distinction that matters here. Those
labels come from `drop:sourceContext=pod|ip;destinationContext=pod` in
[`cilium-values.yaml`](../../k8s/mgmt/bootstrap/cilium-values.yaml), which
reaches existing clusters through
[`cilium-deployment.yml`](../../../.github/workflows/cilium-deployment.yml) —
editing the values file alone does nothing until that workflow runs, and it was
this gap that left production unattributable for two days after the value
merged. A cluster
that has not had that Cilium value applied still reports `hubble_drop_total`
aggregated to `(protocol, reason)` only, and needs the job caught live
(`kubectl get pod -o wide`) with `pfctl -a com.apple/tuist.vmnat -s nat` plus
`ifconfig vlan0` checked on the host instead.

A mis-sourced host can also be found from metrics alone, because none of its cache
traffic completes and its PN VLAN goes nearly silent:

```promql
sort_desc(max_over_time((sum by (instance) (rate(
  node_network_receive_bytes_total{job="tuist-macos-node-exporter",
  device="vlan0"}[30m])))[7d:30m]))
```

Healthy runner hosts peak in the hundreds of kB/s; the mis-sourced host in the
August 2026 incident sat ~1600x below its peers. Use a **7-day peak**: a shorter
window makes a merely idle host look broken, and a floor or minimum does not
separate them because every host, healthy or not, has quiet stretches. Scope this
to the runner fleet: `macos-fleet` and `builders-fleet` hosts sit at a couple of
hundred B/s legitimately, since they run no cache-using VMs.

### Kura cache read faults

```promql
sum by (cluster, pod, route) (
  rate(kura_http_requests_total_total{
    namespace="kura",
    route!~"/_internal/.*|/up|/ready|/status/rollout|/metrics|/_unmatched",
    status=~"5.."
  }[5m])
)
```

- Threshold: `> 0.1`, as a separate threshold expression on `A` rather than a
  comparison inside the PromQL, so the alert value is the failure rate itself
- Pending period: 5 minutes
- Live: rule `cftoutryd1jwge`, titled `Kura - 5xx errors on public cache
  routes`, folder `Alerts`, group `Cache`, receiver `Slack #notifications 2`
  (routed by notification settings, so it carries no `severity` label),
  `no_data_state: OK`. It was originally titled for `/api/cache/module/{id}` and
  ran `sum by (pod) (increase(kura_http_requests_total_total{namespace="kura",
  route="/api/cache/module/{id}", status=~"5.."}[5m])) > 0` — one route, firing
  on a single 5xx.
- **The rule lives in Grafana, not in this repo.** Nothing provisions it from
  here, so an edit means pasting into the rule editor and updating this section
  to match.
- Summary: `Kura pod {{ $labels.pod }} is failing requests on
  {{ $labels.route }} ({{ $labels.cluster }})`

A 5xx on the public cache routes now means one thing: the node could not serve a
request it should have served. The two survivors are an unreachable auth backend
(`kura_auth_decisions_total{result="unavailable"}`) and a transfer that failed
for a reason other than the client going away. Capacity shedding used to land
here as a 503 and no longer does, which is what makes a fixed low threshold
meaningful again — before the split, this rule fired on 25,882 sheds in a single
ten-minute window while the node was healthy and serving 27,418 reads alongside
them.

One expected 5xx source remains: a draining pod answers public requests with
`503 server is draining` until it leaves the Service endpoints, so a rolling
deploy puts a short 5xx blip on this rule. The 5-minute pending period is what
absorbs it; if a deploy ever trips the rule, lengthen the pending period rather
than lowering the threshold, since the blip is bounded by the drain timeout
(`KURA_DRAIN_COMPLETION_TIMEOUT_MS`) and a real fault is not.

Match by exclusion rather than by naming one route: every public cache read
shares the same serving path, so a fault on the CAS or Gradle route is the same
event with a different label, and the exclusion form is the one the `tuist-kura`
dashboard uses for public traffic. There is no `tenant_id` label on
`kura_http_requests_total` — it comes from a join against `kura_node_info` — so
group by `pod`, whose name carries the account (`kura-<account>-<region>-<n>`).

Widening the routes does not make it noisier, because the threshold moves at the
same time. Over the 7 days to 2026-08-21 the original form (one route, fires on
a single 5xx) held its condition for 390 pod-minutes; the form above, across
every public route, holds for 250. It also surfaces something the original could
not see: 20 minutes of 5xx on `/api/cache/module/start`, a write route, on a pod
the old rule never looked at.

#### Before you call a 5xx a fault, check the shed

Capacity shedding reached 429 in two steps, and a node can be running either
half. #12548 moved the artifact **read** shed; the **write** shed — multipart
caps, upload memory, the tmp staging budget, the critical-memory gate and the
replication outbox — followed separately. Through kura@0.25.1 the write shed
still answered 503, so a node merely full of in-flight uploads fired this rule
as if its store had broken. Check the running image before reading a module-route
503 as a fault.

This misfired for real on 2026-08-24: `kura-tuist-scw-fr-par-0` in
`tuist-production` paged on `/api/cache/module/start` with 568 x 503 against 218
successes over a single container lifetime. Nothing was broken. Multipart uploads
orphaned by liveness-kill restarts had pushed the persisted count past the cap,
and every new upload was being turned away.

Since both halves landed, the decisive query is the shed counter, which names
the limit that refused the request:

```promql
sum by (pod, kind) (rate(kura_capacity_sheds_total_total[5m]))
```

`kind` is one of `response_stream` (egress capacity — the only kind the warning
rule below is about), `multipart_uploads`, `multipart_storage`, `upload_memory`,
`tmp_staging`, `memory_pressure_write` or `outbox`. Reach for it before the
older per-subsystem counters: the HTTP status cannot separate these, since 429
is shared by every shed and `kura_http_requests_total` has no method label, so
the routes that serve both reads and writes cannot be split by route either.

On a node predating the write half, fall back to:

```promql
sum by (pod) (rate(kura_multipart_parts_total_total{result="capacity_exceeded"}[5m]))
kura_multipart_uploads
sum by (pod, result) (rate(kura_artifact_reads_total_total{result=~"error"}[5m]))
```

- `kura_multipart_parts_total{result="capacity_exceeded"}` is decisive but covers
  `/api/cache/module/part` only. `/start` and `/complete` have no counter of
  their own.
- **`kura_multipart_uploads` is not the reservation counter.** It is the count of
  *persisted* multipart records (`Store::snapshot` ->
  `count_cf_entries(ROCKSDB_CF_MULTIPART_UPLOADS)`), while admission guards a
  separate atomic. It legitimately reads above the cap — 207 against a cap of
  128 during the incident. Read it as shed pressure, not as the quantity being
  compared to the limit.
- `/api/cache/module/start` has a **second 503 that looks identical**:
  `artifact_exists` failing answers "Failed to inspect artifact". Nothing on the
  route separates the two. What argues for the shed is
  `kura_artifact_reads_total{result=~"error"}` staying empty while
  `/api/cache/module/{id}` keeps serving 200/404.

**The multipart cap is always 128.** `KURA_MULTIPART_MAX_ACTIVE_UPLOADS` is set
nowhere in `kura/ops/` or `infra/kura-controller/`, so every managed instance
runs `DEFAULT_MULTIPART_MAX_ACTIVE_UPLOADS` regardless of how large the instance
is. A bigger node does not get a bigger upload budget.

**An orphaned backlog can outlive the restart that caused it.** Startup seeds the
admission atomic from persisted state, and when that lands over the limit it logs
*"persisted multipart usage starts above its configured limits; rejecting growth
until the janitor reclaims it"*. The janitor runs every 10 minutes, but
`DEFAULT_MULTIPART_UPLOAD_TTL_MS` is **24 hours**, so a node that died mid-wave
can come back already wedged and shed every new upload for up to a day. Grep the
container's startup log for that line before assuming a fresh pod is clean. A
restart cleared it on 2026-08-24, so the day-long wedge is a latent mode, not an
observed one.

Worth watching before it pages: a pod sitting at a non-zero resting
`kura_multipart_uploads` while the rest of the fleet sits at 0 is leaking uploads
toward the same cap.


### Kura cache pod restart loop

```promql
sum by (cluster, pod) (
  increase(kube_pod_container_status_restarts_total{
    namespace="kura",
    container="kura"
  }[6h])
) >= 2
```

- Pending period: 10 minutes
- Severity: critical
- Already created: rule `efvvcl6qu3tvkc`, folder `Alerts`, group `Cache`,
  receiver `Slack #notifications 2`, alongside the other Kura rules. The
  deployed rule keeps the raw `increase(...)` in query A and puts the
  comparison in threshold expression C as `gt 1.5`, matching the house pattern.
- Summary: `Kura cache pod {{ $labels.pod }} restarted
  {{ $values.A.Value | printf "%.0f" }} times in the last 6 hours in
  {{ $labels.cluster }}`

**Nothing covered the `kura` namespace before this.** Two generic restart rules
already existed and neither could have fired: `Pod restarts (possible
overload)` is scoped `namespace="tuist"`, and both it and `Pod CrashLoop /
Frequent Restarts` use thresholds (more than 2 in 15 minutes, more than 5 in an
hour) far above this fault's rate. Check the namespace scope of a generic rule
before assuming it covers a new workload.

**This is the primary rule for the fault.** Backtested over the 7 days to
2026-08-21 across all 30 production Kura pods, sampled every 10 minutes: it
held true at 304, 45 and 35 sample points for the three pods of the account
carrying the heaviest remote-execution traffic, and was never true for any
other pod. Perfect specificity, no tuning required.

Counts in-place container restarts, so a rollout cannot trigger it: a
replacement pod starts its counter at zero. Every restart observed on this
fault reports `Error` with exit code 137 and never `OOMKilled`, because the
container is killed by the kubelet after `Container kura failed liveness
probe`, not by the cgroup out-of-memory killer. A rule keyed on `OOMKilled`
would not have seen any of it.

**Use the 6-hour window, not 1 hour.** The same expression over `[1h]` is
equally specific but much less sensitive: on the same backtest it held at only
1 and 3 sample points for two of the three affected pods, which a 10-minute
pending period may not survive. Restarts on this fault arrive in clusters
separated by hours, so the shorter window keeps falling back below the
threshold between clusters.

A restart is not a cheap recovery here. The node loses its place in the mesh,
its peers log `membership changed: lost peers`, and when it returns every peer
runs a catch-up backfill pass against it: passes applying 27,716 artifacts and
545 MB were logged in the minutes after one restart. That write burst is itself
a trigger for the next stall, so restarts cluster.

### Kura cache telemetry missing

```promql
absent_over_time(up{cluster="tuist-production", job="kura"}[15m])
or
absent_over_time(up{cluster="tuist-staging", job="kura"}[15m])
or
absent_over_time(up{cluster="tuist-canary", job="kura"}[15m])
```

- Pending period: 0 minutes
- Severity: critical
- Already created: rule `ffvvcpp359qm8d`, folder `Alerts`, group `Cache`,
  receiver `Slack #notifications 2`
- Summary: `Kura cache scrape targets have disappeared in {{ $labels.cluster }}`

The paired telemetry rule for the Kura rules that read `up`. Those are
threshold rules with **No Data: Normal**, so they cannot distinguish a healthy
fleet from a scrape configuration that stopped discovering the `kura` namespace
altogether.

**Enumerate the clusters; do not write the bare selector.** `absent_over_time`
is absent-or-nothing across everything the selector matches, so
`absent_over_time(up{job="kura"}[15m])` stays empty while *any* cluster still
has one Kura target. It cannot see a single cluster's targets disappear, which
is the case worth alerting on, and on the one occasion it did fire the result
would carry no `cluster` label for the summary to interpolate. Only equality
matchers survive into the output, so naming each cluster is also what puts
`cluster` on the alert. Same shape as **Kubernetes control-plane scrape
telemetry missing**.

Kura runs in `tuist-production`, `tuist-staging` and `tuist-canary`, and
deliberately not in `tuist-management`. Add a disjunct when a new cluster
starts hosting Kura: a cluster that is absent from this list is not covered,
and nothing will point that out.

**Watch the polarity, which is the reverse of a threshold rule.**
`absent_over_time` returns `1` when the series has been absent for the whole
window and returns *nothing* when it is present, so the healthy state here is
an empty result. **No Data** must therefore be **Normal**, not Alerting;
setting it to Alerting makes the rule fire continuously while the fleet is
healthy. Only **Error** goes to **Alerting**, because a failed evaluation does
mean the safety net is not working. This corrects steps 8 and the Assistant
prompt below, which said to make **No Data** Alerting for telemetry-missing
rules; that reads as correct but inverts the semantics of every
`absent_over_time` rule in this document, so check the deployed configuration
of the older ones too.

### Runner host PN VLAN missing

```promql
count by (instance) (
  node_load1{job="tuist-macos-node-exporter"}
)
unless
count by (instance) (
  node_network_transmit_bytes_total{
    job="tuist-macos-node-exporter",
    device=~"vlan.*"
  }
)
```

- Pending period: 10 minutes (a legitimate re-attachment recreates the
  interface, so don't fire on the gap)
- Severity: critical
- Already created: rule `afuvzdl0z4mwwe`, folder `Alerts`, group `Runners`,
  receiver `Slack #notifications 2`
- Summary: `macOS host {{ $labels.instance }} has no PN VLAN interface — VM
  cache traffic cannot be NAT'd onto the Private Network`

The companion to the rule above, covering the failure it structurally cannot
see. That one fires when VM traffic *reaches* the kura node with the wrong
source. A host with no `vlan*` device has no PN route at all, so its cache
traffic falls to the default route, is deliberately excluded from the
general-internet masquerade (`renderVMNATScript`, so it can never leave with the
host's public source), and dies at the upstream gateway as an RFC1918
destination. Nothing arrives, the policy-drop counter stays at zero, and the
build hangs exactly the same way. Nothing re-converges it either: the operator's
drift loop keys on desired config, not live host state.

`node_load1` is just a per-host liveness anchor — any always-present series from
the same job works. The `unless` yields one series per host that is scraping but
has no VLAN, and nothing at all in the healthy case, which is why **No Data**
must be **Normal** here.

Residual gap, deliberately not covered: a VLAN that exists but has lost its DHCP
address also has no PN route and is invisible to both rules. node_exporter runs
on these hosts without the `netclass` collector, so there is no
`node_network_up` to key an address-level check on. Closing that needs either
that collector enabled or a per-host sink (a Node condition from tart-kubelet,
which already has the DiskPressure probe pattern, or a node_exporter textfile
gauge written by `tuist-pf-vmnat` itself).

### Runner queue not draining

Runner capacity can collapse without a single component reporting a
fault. On 2026-08-13 one of the two Linux fleet nodes
(`bm-tuist-runners-linux-pvv5b-249nj-bkzxh`) stopped being able to
create pod cgroups — kubelet failed every new sandbox with
`mkdir /sys/fs/cgroup/kubepods.slice/...: no space left on device`
after 85 days of uptime. Kubelet reports that per Pod, not as a node
condition, so the node stayed `Ready` with no Memory/Disk/PID pressure
and, being the emptiest node in the fleet, the scheduler preferred it.
Every Pod it accepted sat in `Init:0/4` holding a slot in the
fleet-wide provisioning ceiling (`maxConcurrentPerFleetSelector: 4`)
until the 5-minute start timeout reaped it, and the replacement landed
on the same node. The ceiling stayed saturated by Pods that could never
run, so every sibling shape was refused admission with
`reason="fleet_cap"`. The autoscaler asked for 160 replicas and the
fleet ran 5. Around 111 jobs queued over 5.5 hours. Nothing paged; it
was noticed by a person looking at the queue.

```promql
max by (cluster, env, fleet) (
  tuist_runners_queue_oldest_age_seconds
) > 1800
```

- Pending period: 5 minutes
- Severity: critical
- `affected_service`: the runners component (customer-visible — a job
  that never starts is indistinguishable from CI being down)
- Summary: `Workflow jobs on {{ $labels.fleet }} have been queued for
  over 30 minutes in {{ $labels.cluster }}: the fleet is not draining
  its queue`

Age, not depth, for the same reason the remote-processing rule uses it,
and the reason is already written into the metric's definition in
`Tuist.Runners.PromExPlugin`: a busy fleet serving arrivals promptly and
a fleet that has stopped starting Pods entirely both sit at a non-zero
depth. Only age separates them, and only age keeps climbing while
nothing drains. During this incident depth oscillated between 0 and 111
as bursts arrived and partially cleared, so a depth threshold would
have flapped; the oldest-job age climbed monotonically.

`max by` is required: PromEx polling gauges are reported once per server
pod, so a bare `>` would fire on whichever replica polled first and the
series would double-count.

30 minutes is well clear of a normal wait — a queued job lands on a
Pod within seconds when the fleet is healthy, and even a cold-start
sandbox is minutes — while still catching the stall long before it
reaches the hours this incident ran.

This rule deliberately keys on the queue rather than on any particular
cause. Cgroup exhaustion, an expired runner image pull secret, a
saturated fleet, and a wedged provisioning ceiling all present as "jobs
are queued and not starting", and only the queue itself is common to
all of them.

There is no automated containment behind this alert, by choice: a
per-node circuit breaker was built and dropped because on a two-node
fleet it could quarantine both nodes and stall everything outright (see
`infra/runners-controller/AGENTS.md`). This alert is the detection, and
the response is manual.

When it fires, the first question is whether one node is eating the
fleet's provisioning ceiling:

```bash
kubectl get pods -n tuist-runners -o wide | grep -v Running
```

Runner Pods stuck in `Init` and concentrated on a single node is the
signature. `kubectl describe pod` on one of them names the cause, and
`kubectl cordon <node>` restores throughput on the remaining nodes
immediately. Cordoning does not evict the already-bound Pods, so delete
them too or the ceiling stays occupied until the start timeout reaps
them:

```bash
kubectl delete pod -n tuist-runners -l tuist.dev/runner=true --field-selector spec.nodeName=<node>
```

### Node leaking cgroups

```promql
max by (cluster, env, instance) (
  node_cgroups_cgroups{subsys_name="memory"}
) > 20000
```

- Pending period: 15 minutes
- Severity: warning
- Summary: `{{ $labels.instance }} holds {{ $value }} cgroups — something
  is leaking them, and at exhaustion the node fails every new Pod sandbox`

A node that runs out of cgroups fails every subsequent `mkdir` in
cgroupfs with ENOSPC, which kubelet reports per Pod as
`FailedCreatePodContainer: ... no space left on device`. None of that
surfaces as a node condition: the node stays `Ready` with no
Memory/Disk/PID pressure while being unable to start a single Pod, so
the scheduler keeps feeding it. On 2026-08-13 a Linux runner node
reached that state after 85 days of a kata cgroup-driver leak and took
the fleet's throughput to near zero (see "Runner queue not draining").

The threshold keys on the leak, not on the ceiling. The exact kernel
limit was never pinned down during that incident — the memory controller
was past 130k cgroups, so it is not the 16-bit `MEM_CGROUP_ID_MAX`
figure that circulates — and it does not need to be, because the
diagnostic property is that the count is unbounded rather than that it
is near a specific number.

20000 is chosen against normal, not against the limit: a healthy node
sits in the hundreds, and the failing pair sat around 130k. Anything in
five figures is already anomalous by two orders of magnitude while still
leaving a large multiple of headroom before the observed failure point.

Read it as a rate, not a level. A node flat at 20k has whatever it has;
a node at 5k doubling weekly is the one about to fail. If this fires,
check whether the count grows with container starts
(`kubectl get --raw "/api/v1/nodes/<node>/proxy/metrics" | grep
node_cgroups_cgroups`) — that is the signature of a runtime not cleaning
up, and the fix is the runtime config, not a bigger node.

Counting cgroups rather than matching a directory pattern is what makes
this alert robust, and that paid off immediately. The 2026-08-13 leak
turned out to have two populations of the same size — the literal slice
names at the cgroup root and a second set under
`/sys/fs/cgroup/kata_overhead/` — and the remediation initially swept
only the first. This series counted both throughout, because a leaked
cgroup raises it regardless of where in the tree it sits or what it is
called.

One caveat when reading it after a remediation: `/proc/cgroups` keeps
counting cgroups whose directory is gone but whose charges the kernel
has not reclaimed yet. A freshly swept node can read in the low
thousands here while holding a few dozen directories, and it drains
over the following minutes. Confirm a sweep with
`find /sys/fs/cgroup -type d | wc -l`, not with this metric.

Requires the `cgroups` collector, enabled via `extraArgs` on the
node-exporter DaemonSet in `values.yaml`; it is off in the upstream
chart default.

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

### Remote processing queue has no consumer

`:process_xcresult` and `:process_build` are the two Oban queues whose
consumers live in a *different* deployment from the web tier: the macOS
Tart fleet and the Linux processor pods. That split is the whole reason
this rule exists: when their consumer disappears, every web pod stays
green, every readiness check stays green, and the only thing that moves
is the backlog in a Postgres table nobody was watching.

On 2026-08-12 the xcresult consumer was absent for roughly thirteen
hours. The Tailscale pre-auth key the Tart VMs use had expired, and the
guest's launchd chain hard-ANDs `tailscale up` before `exec tuist start`
(`infra/xcresult-processor-image/tailscale-up.sh`), so the release never
booted. The Pod still reported `1/1 Running`, the Deployment still
reported `Available=True`, and ExternalSecrets still reported
`SecretSynced`. A synced secret says nothing about whether the value
inside it is still valid. Around 4,600 jobs accumulated and roughly
4,000 test runs sat at `status='processing'`. It was reported by a
customer, not by an alert. A structurally different failure with the
identical outward shape (broken host VM to internet NAT on 2026-06-26)
produced the same silent stall, which is why this rule keys on the
queue rather than on any particular cause.

```promql
max by (cluster, env, queue) (
  tuist_oban_queue_oldest_available_age_seconds{
    queue=~"process_xcresult|process_build"
  }
) > 900
```

- Pending period: 5 minutes
- Severity: critical
- Summary: `No consumer is draining the {{ $labels.queue }} Oban queue in
  {{ $labels.cluster }}: the oldest job has been runnable for over 15
  minutes`

`tuist_oban_queue_oldest_available_age_seconds` is emitted by
`Tuist.Oban.PromExPlugin`, which reads the shared `oban_jobs` table
rather than the polling node's own producers. Every node running PromEx
therefore reports it, including the always-healthy web pods, so the
signal survives the complete loss of the deployment that consumes the
queue. `max by` is required: the same gauge is reported once per pod.

Age, not depth. A queue that is never empty because arrivals are served
promptly and a queue with no consumer at all both sit at a non-zero
depth; only age separates them, and only age keeps climbing for as long
as nothing drains. The gauge covers `available` alone, because
`scheduled` and `retryable` carry a *future* run-at, so a healthy retry
backoff would otherwise read as a stall.

15 minutes is well above the normal wait (both queues clear a job within
seconds of it becoming available, and the worker's own retry backoff
tops out at 10 minutes) and far below any usable outage budget. With the
pending period the page lands about 20 minutes in.

The gauge emits an explicit `0` for a queue that has drained since the
previous poll, so a fired alert resolves on its own. Do not "fix" a
stuck alert by adding `or vector(0)`; a gauge stuck at its last non-zero
sample means the zero-emission path regressed.

### Remote processing queue telemetry missing

```promql
absent_over_time(
  tuist_oban_queue_oldest_available_age_seconds{
    cluster="tuist-production", queue="process_xcresult"
  }[10m]
)
or
absent_over_time(
  tuist_oban_queue_oldest_available_age_seconds{
    cluster="tuist-production", queue="process_build"
  }[10m]
)
```

- Pending period: 0 minutes
- Severity: critical
- Summary: `Oban queue-age telemetry is missing for
  {{ $labels.queue }} in {{ $labels.cluster }}`

The queue-age rule is a threshold rule, so it runs with **No Data:
Normal** and cannot tell a healthy queue from a gauge that stopped being
emitted. `Tuist.Oban.PromExPlugin` emits one series per configured queue
on every poll whether or not the queue has work, so absence means the
plugin, the scrape, or the queue's registration went away, not that the
queue is idle. Production only: staging and canary can legitimately run
with no processor deployment at all.

### Swift registry catalog coverage deferred

Same shape as the queue rule above, for the writer rather than a
consumer: the swift-registry-sync pod can be `1/1 Running` with zero
restarts and still not be mirroring anything.

That is not hypothetical. During the July 2026 registry incident the
production pod logged 2,566 GitHub rate-limit failures and dropped nine
consecutive scheduled catalog passes in a little over six hours, while
every availability signal stayed green. Nothing paged, and the first
detection of the resulting catalog drift was a customer issue.

`Tuist.Registry.Swift.SyncWorker` now defers a throttled pass to the
quota reset instead of discarding it, holds the rotation cursor at the
package it stopped on, and counts the packages it gave up on. This rule
reads that count.

```promql
sum by (cluster, env) (
  increase(tuist_registry_swift_sync_coverage_deferred_total[30m])
) >= 3
```

- Pending period: 0 minutes
- Severity: critical
- Label: `affected_service` set to the registry component
- Summary: `The Swift registry mirror deferred {{ $value }} scheduled
  catalog passes in the last 30 minutes in {{ $labels.cluster }}`

Passes, not packages: a single deferred pass is ordinary (the mirror
backs off, the next one catches up), and three inside half an hour means
the deferral is not clearing on its own. The catalog rotates roughly
every ten minutes, so three consecutive deferrals is the whole window.

`reason` separates the causes without changing the threshold, and is
worth reading before acting. `rate_limited` points at the request budget
(check `tuist_github_rate_limit_used` against `tuist_github_rate_limit_limit`
and, if it is genuinely exhausted, at `swiftRegistrySync.syncLimit`).
`missing_credential` means the GitHub App could not issue an installation
token at all. `unauthorized` means GitHub refused the token the mirror
does hold. `all_packages_failed` means every package in a pass failed,
which is the mirror being broken rather than several hundred unrelated
repositories failing at once, and is the shape a credential problem takes
because GitHub answers an invisible repository with 404 rather than 401.
For either, reverting `swiftRegistrySync.githubAppInstallation` falls back
to the personal access token. None of these three is fixed by waiting.

### xcresult processor guest metrics unavailable fleet-wide

The direct detector for "the BEAM inside the Tart VM is not running".
tart-kubelet is not a real kubelet: it implements no container probes at
all and sets `PodReady=True` unconditionally once the VM has an IP
(`infra/tart-kubelet/internal/podagent/reconciler.go`), so Kubernetes
cannot tell a booted VM running the release from a booted VM whose
launchd chain died before it. The `pod-metrics` scrape target *can*: it
terminates on the guest's PromEx endpoint, which only answers when the
release is up. This alert is the readiness probe the platform can't
give us, expressed in the metrics pipeline instead.

```promql
(
  sum by (cluster, env) (up{job="tuist-macos-pod-metrics"}) == 0
)
and
(
  count by (cluster, env) (up{job="tuist-macos-pod-metrics"}) > 0
)
```

- Pending period: 10 minutes
- Severity: critical
- Summary: `No xcresult processor is serving metrics in
  {{ $labels.cluster }}. The queue consumer is down fleet-wide`

The second clause keeps this distinct from `xcresult processor guest
telemetry missing` below: it fires only when targets exist and every one
of them is down, never when the job vanished from discovery.

Fleet-wide rather than per-target because that is what a rollout cannot
produce. `xcresultProcessor.strategy` sets `maxSurge: 0` and the PDB
holds `minAvailable: 1`, so a deploy replaces one Tart VM at a time and
at least one target stays up throughout. Every target down at once is
never a normal state, which is what lets the pending period stay at 10
minutes despite a single VM cycle legitimately taking up to
`progressDeadlineSeconds: 1800`.

### xcresult processor guest metrics unavailable on one host

```promql
min by (cluster, env, instance) (
  min_over_time(up{job="tuist-macos-pod-metrics"}[5m])
) == 0
```

- Pending period: 45 minutes
- Severity: warning
- Summary: `xcresult processor on {{ $labels.instance }} is not serving
  metrics. The fleet is running below capacity`

The half-capacity companion to the rule above, and the one that also
covers a Mac mini that is powered on but never joined the cluster: the
CAPI provider creates the egress Service per `ScalewayAppleSiliconMachine`,
so the scrape target exists from the moment the machine does, whether or
not a processor Pod ever lands on it.

45 minutes is deliberately long. One target is legitimately down for a
full Tart VM teardown + boot on every deploy, and the Deployment budgets
1800s for exactly one such cycle. Anything under that pages on routine
rollouts. Detection speed for a total outage comes from
`Remote processing queue has no consumer` and
`xcresult processor guest metrics unavailable fleet-wide`, not from
this one.

### xcresult processor guest telemetry missing

```promql
absent_over_time(
  up{cluster="tuist-production", job="tuist-macos-pod-metrics"}[10m]
)
or
absent_over_time(
  up{cluster="tuist-staging", job="tuist-macos-pod-metrics"}[10m]
)
or
absent_over_time(
  up{cluster="tuist-canary", job="tuist-macos-pod-metrics"}[10m]
)
```

- Pending period: 0 minutes
- Severity: critical
- Summary: `xcresult processor scrape telemetry is missing in
  {{ $labels.cluster }}`

Covers the discovery layer failing rather than the workload: the
`tuist.dev/macmini-egress` Services being garbage-collected, the
`tuist.dev/fleet` label drifting away from the `.*-macos-fleet` matcher
the Alloy relabel keeps on, or the egress ProxyGroup losing its tailnet
identity. Without this, every rule above silently evaluates to nothing.

### xcresult processor replicas unavailable

```promql
kube_deployment_status_replicas_available{
  namespace=~"tuist|tuist-staging|tuist-canary",
  deployment="tuist-tuist-xcresult-processor"
}
<
kube_deployment_spec_replicas{
  namespace=~"tuist|tuist-staging|tuist-canary",
  deployment="tuist-tuist-xcresult-processor"
}
```

- Pending period: 45 minutes
- Severity: warning
- Summary: `xcresult processor has unavailable replicas in
  {{ $labels.namespace }}`

Catches the scheduling half of the same outage: on 2026-08-12 one of the
two replicas sat `Pending` for over four hours while the Deployment
reported `Available=True MinimumReplicasAvailable` and
`Progressing=True NewReplicaSetAvailable`, because both conditions are
satisfied by `maxUnavailable` rather than by `readyReplicas ==
spec.replicas`. Kubernetes considers that healthy; it is not.

Same 45-minute rationale as the per-host rule: a Tart VM replacement
makes one replica unavailable for a long, legitimate window. Deliberately
does not subsume the metrics rules: a Pod whose VM booted but whose
release never started counts as available here.

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

### Kura shedding cache reads under capacity pressure

```promql
(
  (
    sum by (cluster, pod) (
      rate(kura_capacity_sheds_total_total{namespace="kura", kind="response_stream"}[5m])
    )
    or
    sum by (cluster, pod) (
      rate(kura_http_requests_total_total{namespace="kura", route!~"/_internal/.*|/up|/ready|/status/rollout|/metrics|/_unmatched", status="429"}[5m])
    )
  )
  /
  clamp_min(
    (
      sum by (cluster, pod) (
        rate(kura_capacity_sheds_total_total{namespace="kura", kind="response_stream"}[5m])
      )
      or
      sum by (cluster, pod) (
        rate(kura_http_requests_total_total{namespace="kura", route!~"/_internal/.*|/up|/ready|/status/rollout|/metrics|/_unmatched", status="429"}[5m])
      )
    )
    +
    (
      sum by (cluster, pod) (
        rate(kura_artifact_reads_total_total{result="ok", producer!="reapi"}[5m])
      )
      or
      (
        sum by (cluster, pod) (
          rate(kura_capacity_sheds_total_total{namespace="kura", kind="response_stream"}[5m])
        )
        or
        sum by (cluster, pod) (
          rate(kura_http_requests_total_total{namespace="kura", route!~"/_internal/.*|/up|/ready|/status/rollout|/metrics|/_unmatched", status="429"}[5m])
        )
      ) * 0
    ),
    0.01
  )
)
and
(
  sum by (cluster, pod) (
    rate(kura_capacity_sheds_total_total{namespace="kura", kind="response_stream"}[5m])
  )
  or
  sum by (cluster, pod) (
    rate(kura_http_requests_total_total{namespace="kura", route!~"/_internal/.*|/up|/ready|/status/rollout|/metrics|/_unmatched", status="429"}[5m])
  )
) > 1
```

- Threshold: `> 0.05`, as a separate threshold expression on `A`. The volume
  floor stays inside the PromQL, since `and` filters the series rather than
  reducing it to a boolean, which keeps the shed ratio as the alert value
- Pending period: 10 minutes
- Severity: warning
- Live: rule `dfvv8qn09k1z4b`, folder `Alerts`, group `Cache`, receiver
  `Slack #notifications 2`, `no_data_state: OK`. **Still on the bare-429 query;
  the form above has not been applied yet.** It can be applied at any point --
  before, during or after the rollout -- because the `or` arm makes it correct
  on both images; see below. The query was validated against `grafanacloud-prom`
  via `/api/ds/query` on 2026-08-24: it parses, executes, and returns an empty
  vector on the currently quiet fleet, matching the deployed rule.
- Summary: `Kura pod {{ $labels.pod }} is shedding
  {{ $values.A.Value | humanizePercentage }} of cache reads in
  {{ $labels.cluster }} — it is out of response-stream capacity, not broken`

`$values.A.Value`, not `$value`: the ratio is query `A` and the threshold is a
separate expression, so `$value` renders both refIds rather than the percentage.
`no_data_state: OK` is load-bearing too — the `and` returns an empty vector
whenever the volume floor is not met, which is most of the time.

Kura answers a read it cannot admit a response stream for with `429` and
`Retry-After: 1`. Clients retry, so a shed is a slowdown rather than a failure,
and a short burst is the admission control working.

**Select on `kind`, with a bare-429 fallback.** Every public capacity shed now answers
429 — multipart caps, upload memory, the tmp staging budget, the critical-memory
gate and the replication outbox alongside this one — so an unqualified
`status="429"` numerator mixes write sheds into a ratio whose denominator counts
only reads. That both inflates the number and mislabels the cause, which matters
because this rule's summary asserts response-stream capacity specifically.
Splitting by route does not work either: `kura_http_requests_total` carries no
method label, and `/v1/cache/{hash}`, `/api/metro/cache/{cache_key}`,
`/api/cache/cas/{id}` and `/api/cache/gradle/{cache_key}` each serve reads and
writes under one route template. `kura_capacity_sheds_total{kind}` exists for
exactly this: one series per limit, every value a constant in
`metrics::shed_kind`, so the label cannot grow with traffic. The other kinds are
a capacity signal too, but a different one, and they belong in their own rule
rather than this one.

**The `or` arm is what lets this rule be correct before, during and after the
rollout**, rather than having to be swapped at the exact moment of deploy.
Neither ordering works on its own: repointing the rule ahead of deploy leaves it
reading `NoData` (which `no_data_state: OK` renders as silence, so read sheds go
uncovered), and repointing it afterwards leaves a window where write sheds page
as read pressure. Selecting the kind and falling back to the bare-429 count
where that series is absent is correct in both worlds, and per-pod, so a
half-rolled fleet reads correctly on both sides.

That fallback rests on the series existing from boot. Every kind in
`shed_kind::ALL` is materialised at zero when `Metrics` is constructed, so
"series missing" means "pod is running the old image" and never "new pod that
has not shed a read yet" — the case that would otherwise have its write sheds
counted as read sheds. `metrics::tests::every_shed_kind_is_published_before_the_first_shed`
pins it. Once the whole fleet is on the new image the `or` arm is dead weight
and can be dropped, but it costs nothing to leave. What matters is the share of
reads being shed and for how long, which is why this is rate-relative: an
absolute count fires on the busiest tenant first no matter how well they are
being served, and the same count means very different things at 200 req/s and at
20,000 req/s.

The threshold is a ratio because the lever is capacity, and the decision it
feeds is a capacity decision: sustained shedding means the tenant's peak demand
is above what their node's uplink can deliver, so the fix is egress budget or
placement, not a restart. Which admission stage refused breaks down as:

```promql
sum by (pod, outcome) (
  rate(kura_response_stream_admissions_total_total{
    outcome=~"timeout|queue_full|degraded_timeout|degraded_memory_unavailable"
  }[5m])
)
```

Note the doubled suffix: the counter is registered as
`kura_response_stream_admissions_total` and reaches Grafana Cloud as
`..._total_total`, the same as `kura_http_requests_total_total`. Do not build
the alert itself on that counter. One request can record more than one outcome —
a read that records `queue_full` on its full-size attempt and then succeeds on
the degraded pool records `degraded` too — so it counts admission attempts, not
shed requests. `kura_capacity_sheds_total` is one increment per shed request and
is the unambiguous signal; the HTTP status is one value per request but is now
shared across every kind of shed.

**Two details in this query are load-bearing, both measured over the 7 days to
2026-08-21 using the pre-change 503s as a proxy for the 429s.**

The denominator is the reads that wanted bytes: successful artifact reads plus
sheds. It cannot be assembled from HTTP status alone. Excluding 404s matters
first — the module cache runs a high miss rate and 404s were 12.3M of 21.9M
public requests in that week, so counting them reports 6.9% where the reads
that mattered were shed at 17.2%, and the number would drift down as the hit
rate improves, which is exactly backwards. But `status="200"` is not the
complement either: **`kura_http_requests_total` carries no method label**, so a
200 there is also an Nx or Metro `PUT`, a repeat Gradle upload (201 when new,
**200 when it already exists**), or a `/status/cluster` poll, none of which
wanted artifact bytes. Only the CAS write escapes it, by answering 204.

`kura_artifact_reads_total{result="ok"}` is the honest denominator: it counts
artifact reads that produced bytes and nothing else, and it is recorded on both
the accelerated and the streaming serving path. Exclude `producer="reapi"` or
gRPC reads swamp the ratio — they are 7.8M of the fleet's 15.7M weekly reads
and they never carry an HTTP status, so a REAPI-heavy pod would show a shed
ratio near zero no matter how hard it was shedding over HTTP.

The `or ... * 0` around it is not decoration. `+` between two metrics matches
on labels, so a pod with sheds but **no** successful reads in the window — a
node shedding everything, the case the rule most needs to catch — has no
matching series on the right and drops out of the result entirely. The `or`
supplies a zero for those pods so the ratio stays defined at 1.0.

The absolute floor exists because a ratio alone fires on idle pods: a pod
answering two requests, one of them shed, reads as 50%. Without the floor,
`kura-tuist-scw-fr-par-0` spent 35 minutes of that week above 5% purely on low
volume; with it, 15. That pod recorded **zero** response-stream admission
failures over the same week, so its 503s were never sheds and will not appear as
429s at all — worth remembering when reading a ratio on a quiet pod.

For scale, the rule would have been quiet: 90 and 85 minutes above threshold in
that week on the two busy pods, in bursts that peaked between 47% and 100%, with
at least one burst per pod holding above 5% for a full 10 minutes. Nothing else
in the fleet came close.

### Swift registry release work repeatedly deferred

```promql
sum by (cluster, env) (
  increase(tuist_registry_swift_release_deferred_total[1h])
) > 50
```

- Pending period: 10 minutes
- Summary: `{{ $value }} Swift registry release jobs were deferred in the
  last hour in {{ $labels.cluster }}`

Deferred release jobs keep their arguments and run once the throttling
clears, so a handful is the mechanism working. A sustained rate means new
versions are not reaching the catalog, which surfaces to customers as a
version that never appears rather than as an error. Pairs with the
critical coverage rule above: that one fires when whole passes stop,
this one when individual releases pile up behind throttling.

### Swift registry packages skipped without being read

```promql
sum by (cluster, env) (
  increase(tuist_registry_swift_sync_package_skipped_total[1h])
) > 100
```

- Pending period: 10 minutes
- Summary: `The Swift registry mirror passed over {{ $value }} packages
  without reading their tags in the last hour in {{ $labels.cluster }}`

Distinct from the deferral rules: these are packages the pass moved past
after a non-throttling failure, so the cursor has already rotated beyond
them and they wait a full catalog rotation for another look. A steady
rate here is upstream repositories going away or a scope problem on the
mirror's credential, not a quota problem.

### Kura cache pod failing scrapes

```promql
sum by (cluster, pod) (
  count_over_time((up{job="kura"} == 0)[6h:1m])
) >= 2
```

- Pending period: 5 minutes
- Severity: warning
- Already created: rule `cfvvcmpw0wqv4f`, folder `Alerts`, group `Cache`,
  receiver `Slack #notifications 2`
- Summary: `Kura cache pod {{ $labels.pod }} failed
  {{ $values.A.Value | printf "%.0f" }} scrapes in the last 6 hours in
  {{ $labels.cluster }}`

Kura serves `/metrics`, `/up` and `/ready` from the same axum server on the
same port, so an Alloy scrape timeout and a kubelet probe timeout are two
collectors observing the same event. That makes this the only rule that can see
a stall the kubelet does *not* act on, which matters because most stalls never
become restarts: one pod logged 55 readiness and 30 liveness timeouts over 23
hours, of which only 10 crossed the three-consecutive-failure liveness
threshold.

**Its coverage is partial, and it is a warning for that reason.** Measured over
the 24 hours to 2026-08-21, three pods restarted 15 times between them but the
whole production fleet produced only 15 failed scrapes, 13 of them on one pod;
a pod that restarted three times produced **zero**. A stall costs roughly one
scrape at the default interval, and the container often comes back before the
next one lands. Treat this rule as supplementary detail on top of **Kura cache
pod restart loop**, never as the detector.

Do not reach for a ratio here. An earlier version used
`avg_over_time(up[30m]) < 0.9`, which the same measurement rules out: a single
stall plus restart costs about 2 of 30 scrapes in the window, or 0.93, so it
sits above any threshold loose enough to survive a rolling update. Counting
absolute failures is what makes a one-scrape event visible.

### Kura metadata store write buffer saturated

```promql
max by (cluster, pod) (
  kura_rocksdb_write_buffer_usage_bytes
  /
  kura_rocksdb_write_buffer_capacity_bytes
) > 0.95
```

- Pending period: 10 minutes
- Severity: warning
- Already created: rule `dfvvcp2lfgb9cd`, folder `Alerts`, group `Cache`,
  receiver `Slack #notifications 2`
- Summary: `Kura metadata store write buffer is
  {{ $values.A.Value | humanizePercentage }} full on {{ $labels.pod }} in
  {{ $labels.cluster }}`

The mechanism behind the two rules above, and the only one of the three visible
*before* the pod stops answering.

Kura builds its metadata store with a RocksDB `WriteBufferManager` whose stall
flag is enabled (`kura/src/store.rs`). Once memtable memory reaches the pool
size, RocksDB blocks every thread inside its write call until a flush drains
it. Those write calls run directly on tokio worker threads rather than on the
blocking pool, so a saturated write buffer parks the runtime itself: the probe
handlers stop being scheduled even though `/up` reads nothing but process-local
config and takes no lock. Managed instances pin the pool with
`KURA_METADATA_STORE_WRITE_BUFFER_POOL_BYTES`, set in
`kura/ops/helm/kura/values-managed.yaml` and in the kura-controller, to a value
below what the process would otherwise derive from its memory limit, and the
same allocation is shared with the block cache, so memtable growth evicts the
read cache that the eviction scan depends on.

The largest batch the store writes is CAS segment eviction, which deletes every
artifact in a 512 MiB segment plus every action-cache entry cascading off those
blobs in a single batch, and scans that whole segment index synchronously to
build it. Four restarts across three pods and two node pools on 2026-08-21 each
followed an eviction by 49 to 63 seconds, which is what three liveness failures
at `periodSeconds: 20` costs. The cascade size does not predict it: evictions
cascading 47 and 305 entries stalled the pod exactly as ones cascading 4,555 and
7,360 did, so treat the eviction itself as the trigger rather than its fanout.

**The threshold is 0.95 because busy is not the same as stalled.** Over the 24
hours to 2026-08-21 the idle fleet baseline was 0.063, five healthy pods across
three regions peaked at 0.844 under ordinary load, and exactly one pod exceeded
the pool size at 1.125. A threshold at 0.9, and certainly one at 0.8, would
page on the normal peak. Confirm this distribution before tightening it: the
gauge is unproven as a leading indicator, and 0.95 was chosen to sit between the
measured normal peak and the one measured excursion rather than from any
property of RocksDB.

The deployed rule sets **Error** to **OK**: the provisioning API accepts only
`OK`, `Alerting` and `Error` for that field, so the **Keep Last State** the
capacity warnings use is reachable from the UI but not from a provisioned
create. `OK` keeps a data-source error from fanning out a warning, which is the
same intent.

This gauge only exists while the pod is scrapeable, which is precisely the
window this rule is for: once the stall is underway the series stops arriving
and the restart rule takes over.

### Worker node pool stuck mid-rollout

Catches a worker MachineDeployment that started replacing Machines and cannot
finish. Desired-vs-ready is blind to this: a stalled roll keeps every Machine
it already has Ready, so `ready == spec` the whole time and the pool looks
healthy while it silently stops receiving template changes. That is how
`tuist-runners-linux` went two months — from 2026-06-17 — with two Ready
Machines, one of them up to date, and no signal at all.

This covers a roll that has not yet *produced* every Machine it needs, most
importantly a bare-metal pool whose hosts are all claimed and so cannot surge
a replacement, meaning the roll never starts (fixed by `maxSurge: 0` /
`maxUnavailable: 1` on the `bare-metal-worker` class).

It does **not** cover a drain that cannot finish. Once the last replacement is
Ready, `up_to_date == spec` even though the old Machine is still stuck in
`Deleting`, and this query goes quiet. "Worker pool has a Machine it cannot
delete" below is the rule for that half.

```promql
kube_customresource_machinedeployment_up_to_date_replicas{
  cluster="tuist-management"
}
<
kube_customresource_machinedeployment_spec_replicas{
  cluster="tuist-management"
}
```

- Pending period: 24 hours
- Summary: `Worker pool {{ $labels.machinedeployment }} ({{ $labels.workload_cluster }}) has been mid-rollout for a day`

The pending period is set against a healthy *worst-case* roll, and on the
bare-metal runner pools that is dominated by waiting for jobs, not by
provisioning. Runner Pods drain with `WaitCompleted`, so a node is only
replaced once its in-flight jobs finish, and a Linux job can run up to six
hours. `installimage` adds ~8-15 minutes on top. This series stays below
`spec.replicas` for the *whole* roll rather than per node, so a two-host
pool replacing both nodes sequentially is legitimately mid-rollout for
around 13 hours.

Anything under that would fire on a perfectly healthy roll, which is worse
than firing late — an alert that cries wolf on the expected path gets
muted, and this is the only signal covering a class of failure that
previously went unnoticed for two months. Twenty-four hours clears the
worst case with margin and still catches a wedge the next day.

### Worker pool has a Machine it cannot delete

Catches a Machine whose drain never completes. Cluster API's ClusterClass sets
`nodeDrainTimeoutSeconds: 0`, meaning wait forever, because runner Pods drain
with `WaitCompleted` and any finite cap is a promise to kill a customer's CI job.
The accepted cost is that a drain which can *never* finish holds the roll open
indefinitely, and the whole arrangement is predicated on that being loud.

Every other exported series is blind to it. The pool keeps producing its full
complement of up-to-date, Ready Machines, so `up_to_date`, `ready`, and
`available` all equal `spec` while the surplus Machine sits in `Deleting`.
Only `status.replicas`, which counts Machines the MachineDeployment still owns
including ones being deleted, rises above `spec`.

That is how `tuist-md-processor` went 14 days from 2026-07-31 at
`spec=2 replicas=3 up_to_date=2 ready=2`, blocked on two single-instance CNPG
clusters (`tuist-ops/tuist-ops-pg`, `once-production/once-postgres`) whose
`<cluster>-primary` PodDisruptionBudget selects the only pod they have and can
therefore never allow a disruption.

```promql
kube_customresource_machinedeployment_replicas{
  cluster="tuist-management"
}
>
kube_customresource_machinedeployment_spec_replicas{
  cluster="tuist-management"
}
```

- Pending period: 8 hours
- Summary: `Worker pool {{ $labels.machinedeployment }} ({{ $labels.workload_cluster }}) has a Machine it cannot delete`

Two healthy paths put `replicas` above `spec`, and the pending period has to
clear the slower of them.

A **rollout** surges a replacement before deleting the old Machine, but only on
the `hcloud-worker` class: `bare-metal-worker` runs `maxSurge: 0` and never
surges. On an hcloud pool the slowest legitimate term is CNPG's
`terminationGracePeriodSeconds: 1800`, so a three-node pool rolling
sequentially holds a surplus Machine for close to two hours.

A **scale-down** is the binding case, and it is the reason this is not a
four-hour rule. `maxSurge` governs rollouts only. Lowering `spec.replicas`
puts `replicas` above `spec` immediately, on every class including bare metal,
and the gap stays open for the whole drain of the Machine being removed.
Cluster API drains a scale-down exactly like a rollout, so on a runner pool
that means `WaitCompleted` waiting on an in-flight CI job, legitimately up to
six hours. Scaling `runners-linux` from two replicas to one would otherwise
page at four hours every time. Eight clears the six-hour job ceiling with
margin.

Excluding the runner pools by name and keeping four hours was the alternative.
Rejected: it hardcodes pool names that rot, and it would leave a wedged drain
on exactly the pools where drains are slowest with no coverage at all. One
rule that fires late on every pool beats a fast rule with a hole in it.

Still far tighter than the 24 hours on "stuck mid-rollout", which additionally
has to sit above a *whole* multi-node bare-metal roll rather than a single
Machine's drain.

### Pod cannot be scheduled

Catches a Pod the scheduler has given up placing. Nothing else in this
document covers it, because an unscheduled Pod produces none of the
signals the other workload rules read: it has no container, so there is
no waiting reason, no termination reason, and no restart count, and it
never had a ready endpoint to lose. Its Services keep existing with zero
endpoints, which reads as "no traffic" rather than "no backend".

That is how `registry/registry-pg-1` — the sole instance of a
CloudNativePG cluster — sat `Pending` in production from 2026-07-06 to
2026-08-19 without anyone noticing. Its volume had been provisioned
against a node that was later destroyed, and Hetzner Cloud Volumes are
location-bound, so the replacement Pod could not satisfy the volume's
node affinity anywhere in the cluster. All three of that cluster's
Services served zero endpoints for six weeks.

```promql
max by (cluster, namespace, pod) (
  kube_pod_status_unschedulable{
    cluster="tuist-production",
    namespace!="tuist-runners"
  }
) == 1
```

- Pending period: 30 minutes
- Severity: warning
- No-data state: OK, and the same for the execution-error state
- Summary: `Pod {{ $labels.namespace }}/{{ $labels.pod }} has been unschedulable for 30 minutes in {{ $labels.cluster }}`

The no-data state is not incidental. Production's healthy baseline for
this query is *no series at all*, so the rule sits in no-data rather than
at zero whenever nothing is wrong. Left at the `Alerting` default it
would fire permanently from the moment it is created.

The `cluster` scope is also load-bearing, and this rule was documented
without it first. When it was written the unscoped query matched 15
permanently unschedulable Pods in `tuist-staging`, so saving it would
have fired 15 alerts on its first evaluation. That is the failure mode
the *Worker node pool stuck mid-rollout* rule warns about in its own
pending-period note: a rule that cries wolf on the expected path gets
muted, and a muted rule is worth less than no rule.

Those 15 turned out to be orphans rather than a reason to widen the rule,
and were cleared on 2026-08-19:

- 11 `kura-<account>-staging` instances stranded in the retired
  `hetzner-staging-runners` region, whose `kura` node pool was deleted
  with it. Their Postgres rows were already gone, and
  `reconcile_retired_region_servers` drives teardown from those rows, so
  the orphaned `KuraInstance` CRs were invisible to it permanently.
- 3 belonging to `kgw-…-eu-central-controller`, left behind when the
  per-account Kura gateway was removed in
  [#11644](https://github.com/tuist/tuist/pull/11644). Helm does not prune
  CRDs, so the CRD and its CR outlived the controller that reconciled
  them, and the CR's finalizer had to be cleared by hand because nothing
  was left to process it.
- 1 `tailscale-operator` subnet-router Pod, which is churn rather than a
  stuck Pod: the operator replaces it every few minutes, so no single
  instance survives the pending period.

Staging is clean enough to alert on today. The scope stays at production
because that is what the deployed rule uses, and the two should not drift;
widening it is a deliberate follow-up rather than an oversight. Before
doing so, confirm the subnet-router churn still never persists past 30
minutes, because one instance did sit unschedulable for 18 consecutive
hours in the 48 hours before the cleanup.

Validate any change to this query against live data before saving it. The
staging noise above was invisible in review and only showed up by running
the expression over a 48-hour window.

No metric change is needed. The kube-state-metrics tuning in
[`values.yaml`](./values.yaml) already keeps `kube_pod_status_unschedulable`
cluster-wide while dropping the rest of `kube_pod_*` for the runner
namespace, on the grounds that it is a cheap placement signal — so the
series for this incident existed in Grafana Cloud the whole time and
nothing read it.

`tuist-runners` is excluded rather than alerted on. Unschedulable Pods
are an expected steady state there: the autoscaler deliberately asks for
more replicas than the fleet can bin-pack, and the surplus stays
unschedulable until hosts free up. The real runner-side failure is
already covered by *Runner queue not draining*, which measures queue age
and does not confuse a capacity ceiling with a fault. Idle Linux runners
would not have matched this rule in any case — they are `Pending` because
their dispatch poller runs as an init container, not because the
scheduler could not place them.

Thirty minutes clears the ordinary path where a Pod waits on the cluster
autoscaler to add a node, and is short enough that a volume-affinity or
taint mistake surfaces the same morning instead of six weeks later. This
is a warning rather than a page because it fires on any production
workload in any namespace: the Pod that motivated it was critical, but
most Pods that briefly cannot schedule are not.

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

### Runner job replica divergence

```promql
max by (fleet) (
  tuist_runners_replica_divergence_count{env="production"}
) > 0
```

- Pending period: 15 minutes
- Already created: rule `ffvr99w48mltsb`, folder `Alerts`, group `Runners`,
  receiver `Slack #notifications 2`.
- **Created paused.** The gauge counts against a 7-day `enqueued_at` floor, and
  the divergence from the 2026-08-19 log-archiver bug sits inside that window,
  so the rule would fire continuously until those rows age out. Unpause once
  `max by (fleet) (tuist_runners_replica_divergence_count{env="production"})`
  reads 0, or once the affected rows are repaired.
- Counts jobs whose ClickHouse `runner_jobs` row is still
  `queued`/`claimed`/`running` while the authoritative Postgres
  `runner_workflow_jobs` row is terminal. The server-side poll already excludes
  rows younger than a 5-minute settle window, so in-flight jobs and normal
  outbox lag are not counted and steady state is 0.
- Data-correctness, not availability: dispatch reads Postgres directly, so jobs
  keep running while this fires. What breaks is analytics —
  `Runners.Analytics.jobs_duration` filters on a terminal status with non-null
  `started_at`/`completed_at`, so a diverged job drops out of customer-facing
  duration percentiles and success counts.
- Threshold is `> 0` rather than a tolerance band: the outbox makes divergence
  transient by construction (the ClickHouse insert precedes the outbox delete in
  one transaction), so anything surviving the settle window is a row that will
  not converge on its own.
- Summary: `Runner fleet {{ $labels.fleet }}: {{ $values.A.Value }} job(s) stuck
  non-terminal in ClickHouse while Postgres says they finished`

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
8. Set **No Data** to **Normal** on the telemetry-missing rules as well.
   `absent_over_time` returns a series only when the metric is *gone*, so an
   empty result is the healthy state exactly as it is for a threshold rule.
   Setting **No Data** to **Alerting** on one of these inverts it and the rule
   fires continuously while everything is healthy.
9. Set **Error** to **Alerting** for the critical availability and
   telemetry-missing rules. Use **Keep Last State** for capacity and latency
   warnings so a data-source evaluation error does not fan out into unrelated
   warnings. Note that **Keep Last State** is reachable from the UI but not
   from the provisioning API, which accepts only `OK`, `Alerting` and `Error`;
   use `OK` there for the same intent.
10. Write value interpolations as `{{ $values.A.Value }}`, not `{{ $value }}`.
    Every rule here is a data query plus a separate threshold expression, and on
    a multi-ref-id rule `$value` expands to a string listing each ref id and its
    value (`[ var='C0' labels={...} value=1 ]`) rather than the number from A.
    That also breaks any pipe into `humanizePercentage` or `printf`, which want
    a number. `{{ $labels.x }}` is unaffected.
11. Add the suggested summary, a `severity` label, and the notification contact
   point used by the infrastructure team. Add `affected_service` to
   customer-visible rules as described in **Routing to Grafana IRM** above.
12. Preview the raw metric selector and the final comparison separately against
    recent data before saving it.
13. For a rule whose healthy state is an empty result *and* whose unhealthy
    state depends on the series existing (`Remote processing queue has no
    consumer`, `xcresult processor guest metrics unavailable fleet-wide`),
    confirm the paired telemetry-missing rule exists before relying on it.
    A threshold rule with **No Data: Normal** cannot distinguish "healthy"
    from "the exporter stopped shipping this metric", which is precisely the
    failure mode these were written for.

The same rules can be created with Grafana Assistant. Give it this prompt:

```text
Create Grafana-managed alert rules from
infra/helm/k8s-monitoring/alerts.md. Use the Grafana Cloud metrics data source,
preserve every query and pending period exactly, put the rules in a folder
named Tuist infrastructure, add the suggested summary as the annotation, and
route critical and warning severities through our existing infrastructure
notification policy. Configure No Data as Normal for EVERY rule, including the
telemetry-missing ones: those use absent_over_time, which returns a series only
when the metric is gone, so an empty result is the healthy state and No Data as
Alerting would make them fire continuously while healthy. Configure Error as
Alerting for critical availability and telemetry-missing rules, and Keep Last
State for warning rules. Group
notifications by cluster and alert name. Preview each raw metric selector and
final comparison against the last seven days, report any selector with no
matching series, and show me the resulting rules before saving.
```
