# Management node Talos patches and Hetzner resources

The management cluster is a single Talos node (`tuist-mgmt`) in Hetzner Cloud
project `tuist-mgmt`.

- `hetzner.yaml` declares the Hetzner resources around it: the private network,
  and the `tuist-mgmt-api` load balancer in front of the Kubernetes API with a
  primary IPv4 of the same name, so its address survives a load balancer
  recreate. The `hetzner` job in `.github/workflows/mgmt-cluster-apply.yml`
  reconciles it on merge to main with
  `infra/mise/tasks/mgmt/reconcile-hetzner.sh`, after printing the planned
  changes. The token lives in the `tuist-k8s-mgmt-hetzner` vault, which only
  that job's `mgmt-hetzner` environment can read.
- The other files are Talos machine config patches, applied by hand with
  `talosctl`. Nothing in CI or Flux applies them.

To preview the Hetzner changes locally (`CI=1` keeps the repo's mise
postinstall hook from running `tuist setup`; `op run` passes the token to
this one command only):

```bash
HCLOUD_TOKEN=op://tuist-k8s-mgmt-hetzner/hetzner-tuist-mgmt/credential \
  CI=1 op run -- mise exec -- infra/mise/tasks/mgmt/reconcile-hetzner.sh
```

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
