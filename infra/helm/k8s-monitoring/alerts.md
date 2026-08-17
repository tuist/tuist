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
) > 0.5
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

**The threshold is `> 0.5`, not `> 0`, and the window is `[5m]`, not `[10m]`.**
Both matter, and an earlier version of this rule had neither:

- These nodes do **not** sit at exactly zero. Over any given week the production
  node logs dozens of Policy-denied episodes, and roughly a fifth of all 30-minute
  buckets are non-zero. A `> 0` threshold treats every one of them as a critical
  page.
- A **kura-controller rollout** produces a small burst of Policy-denied ingress on
  *all four* kura-hosting nodes at once, within seconds of the new ReplicaSet
  appearing. Roughly half of rollouts do it, and since every merge to `main` rolls
  the controller, that is a recurring false page. Observed magnitudes are 0.02 to
  0.10 packets/s, an order of magnitude below the ~1-2/s of a genuinely stuck job,
  so a 0.5 floor separates them cleanly. The mechanism is unproven: the policy
  object is patched, never recreated (`reconcileNetworkPolicy` uses
  `controllerutil.CreateOrUpdate`), so the suspect is transient identity resolution
  on the `PodSelector` rules rather than a default-deny gap.
- `rate(...[10m])` stays non-zero for a full 10 minutes after the *last* dropped
  packet. Paired with a 10-minute pending period that let a ~4-minute burst hold the
  condition for ~14 minutes and page as critical. `[5m]` keeps the pending period
  meaning "still dropping" rather than "dropped recently".

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
falling back to baseline within a scrape of it being cancelled. Note that baseline
is low but not zero, which is why the rule needs a magnitude floor rather than a
bare `> 0`.

Note the counter carries no source address, so it says *that* a host is
mis-sourced but not *which* one. Correlating it back to a Mac mini currently
needs Hubble flow metrics with source labels on the cache node, or catching the
job live (`kubectl get pod -o wide`) and checking
`pfctl -a com.apple/tuist.vmnat -s nat` plus `ifconfig vlan0` on that host.

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

### Worker node pool stuck mid-rollout

Catches a worker MachineDeployment that started replacing Machines and cannot
finish. Desired-vs-ready is blind to this: a stalled roll keeps every Machine
it already has Ready, so `ready == spec` the whole time and the pool looks
healthy while it silently stops receiving template changes. That is how
`tuist-runners-linux` went two months — from 2026-06-17 — with two Ready
Machines, one of them up to date, and no signal at all.

Two distinct failures land here. A bare-metal pool whose hosts are all
claimed cannot surge a replacement, so the roll never starts (fixed by
`maxSurge: 0` / `maxUnavailable: 1` on the `bare-metal-worker` class). And a
drain that cannot complete holds the roll open — expected briefly, since
runner Pods are drained with `WaitCompleted` and a node waits for its
in-flight CI jobs, but not for hours.

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
   point used by the infrastructure team. Add `affected_service` to
   customer-visible rules as described in **Routing to Grafana IRM** above.
10. Preview the raw metric selector and the final comparison separately against
    recent data before saving it.
11. For a rule whose healthy state is an empty result *and* whose unhealthy
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
notification policy. Configure No Data and Error as Alerting for every
explicit telemetry-missing rule. Configure No Data as Normal for every
threshold rule. Configure Error as Alerting for critical availability and
telemetry-missing rules, and Keep Last State for warning rules. Group
notifications by cluster and alert name. Preview each raw metric selector and
final comparison against the last seven days, report any selector with no
matching series, and show me the resulting rules before saving.
```
