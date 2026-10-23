# Management node Talos patches

The management cluster is a single Talos node (`tuist-mgmt`). These files are
Talos machine config patches, applied by hand with `talosctl`. Nothing in CI
or Flux applies them.

The operator talosconfig is the `talosconfig: tuist-mgmt` document in the
1Password `Development` vault. The node is reachable over the tailnet at
`100.92.208.109` (see [`../tailscale.yaml`](../tailscale.yaml)).

```bash
op document get "talosconfig: tuist-mgmt" --vault Development > /tmp/talosconfig
export TALOSCONFIG=/tmp/talosconfig
```

## `control-plane-resources.yaml`

Sets memory limits on the kube-apiserver, kube-controller-manager and
kube-scheduler static pods.

Talos runs a userspace OOM controller (`runtime.OOMController`, on by default)
that SIGKILLs whole pod cgroups when memory pressure (PSI `memory_full_avg10`)
goes above 12%. Its default ranking skips any cgroup that has a memory limit and
otherwise picks the largest Burstable or BestEffort pod. Without a limit, that
is the kube-apiserver. Kubernetes reports the kill only as `SandboxChanged` and
exit code 137, and the kernel `oom_kill` counter does not change. Talos logs
each kill:

```bash
talosctl -n 100.92.208.109 -e 100.92.208.109 logs machined | grep OOM
```

Preview, then apply. The change applies without a reboot. Talos re-renders the
static pod manifests, so the three control-plane pods restart once:

```bash
talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/control-plane-resources.yaml --dry-run
talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/control-plane-resources.yaml
```

Verify:

```bash
kubectl -n kube-system get pod kube-apiserver-tuist-mgmt \
  -o jsonpath='{.spec.containers[0].resources}'
```

Raise a limit if the component's working set gets close to it
(`container_memory_working_set_bytes{cluster="tuist-management", namespace="kube-system"}`).
Crossing it means a kernel OOM kill of that one container.

## `apiserver-metric-labels-file.yaml` and `apiserver-metric-labels.yaml`

The management cluster's source side of "API-server aggregation must happen
before export" in
[`infra/helm/k8s-monitoring/README.md`](../../../helm/k8s-monitoring/README.md).
The workload clusters get this from the `aggregateApiServerMetrics`
ClusterClass variable; this node is not a CAPI cluster, so it gets the same
allow-list as two Talos patches. The API server then records `component`,
`dry_run`, `group`, `resource`, `scope`, `subresource` and `version` on
`apiserver_request_total`, `apiserver_request_duration_seconds` and
`apiserver_request_terminations_total` as `unexpected`, and the collector's
legacy `labeldrop` stops producing duplicate samples.

Apply them in two phases. This is the only API server, and its static pod
cannot start if the mounted file is missing, so the file must exist before the
flag points at it.

Phase 1 writes the file. Preview, then apply with `--mode=no-reboot` so Talos
refuses rather than reboots if it can't write the file live:

```bash
talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/apiserver-metric-labels-file.yaml --dry-run
talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/apiserver-metric-labels-file.yaml --mode=no-reboot
talosctl -n 100.92.208.109 -e 100.92.208.109 read /var/lib/kube-apiserver/metric-labels.yaml
```

The read must print the 20 `"metric,label": "__none__"` lines. If the apply is
refused, or the read fails, the file is only written at boot: stop here and
schedule a node reboot (the management API is down while it boots) before
phase 2.

Phase 2 points the API server at it. Talos re-renders the static pod, so the
API server restarts once:

```bash
talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/apiserver-metric-labels.yaml --dry-run
talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/apiserver-metric-labels.yaml --mode=no-reboot
```

Verify. Readiness is not enough: Kubernetes logs a manifest read or parse
failure and starts without the allow-list.

```bash
talosctl -n 100.92.208.109 -e 100.92.208.109 get staticpods kube-apiserver -o yaml \
  | grep -E 'allow-metric-labels-manifest|metric-labels.yaml|runAsUser'
kubectl -n kube-system logs kube-apiserver-tuist-mgmt | grep -i -E 'metric-labels|allowlist'
kubectl get --raw /metrics \
  | grep -E '^apiserver_request_(total|duration_seconds_bucket|terminations_total)\{' \
  | grep -o -E '(component|dry_run|group|resource|scope|subresource|version)="[^"]*"' | sort | uniq -c
```

The last command must only show `="unexpected"` values. Then, in Grafana,
`scrape_samples_scraped{job="tuist-kube-apiserver", cluster="tuist-management"}`
steps down, and the duplicate-timestamp lines for `cluster="tuist-management"`
in `grafanacloud-tuist-usage-insights` stop. Only after that set
`k8s-monitoring.global.apiServerMetricsAggregated: true` in
`infra/helm/k8s-monitoring/values-management.yaml`.

Rolling back before that chart gate is set: remove the flag and the volume
(`talosctl edit machineconfig`, or a JSON patch with `op: remove` on
`/cluster/apiServer/extraArgs/allow-metric-labels-manifest` and the volume's
index under `/cluster/apiServer/extraVolumes`). After the chart gate is set,
revert the gate first; never run the `labeldrop`-free collector against an
unaggregated API server.
