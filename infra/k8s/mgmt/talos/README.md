# Management node Talos patches and Hetzner resources

The management cluster is a single Talos node (`tuist-mgmt`) in Hetzner Cloud
project `tuist-mgmt`. Both of its layers are reconciled on merge to main by
`.github/workflows/mgmt-cluster-apply.yml`, which prints the planned changes
before applying them.

- `hetzner.yaml` declares the Hetzner resources around it: the private network,
  and the `tuist-mgmt-api` load balancer in front of the Kubernetes API with a
  primary IPv4 of the same name, so its address survives a load balancer
  recreate. The `hetzner` job applies it with
  `infra/mise/tasks/mgmt/reconcile-hetzner.sh`. The token lives in the
  `tuist-k8s-mgmt-hetzner` vault, which only that job's `mgmt-hetzner`
  environment can read.
- `patches/` holds Talos machine config patches for every control-plane node.
  The `talos` job applies them with `infra/mise/tasks/mgmt/reconcile-talos.sh`.

## How the patches are applied

The Talos API is reachable only over the tailnet, and CI stays off it. Instead,
the script runs `talosctl` in a Job in namespace `mgmt-talos`, using a
credential Talos mints for the `talos-patcher` ServiceAccount in
[`../talos-patcher.yaml`](../talos-patcher.yaml) (`patches/10-talos-api-access.yaml`
allows it). That credential exists only while a run is in progress: the
script creates the ServiceAccount at the start and deletes it and its Secret
on exit, because every principal with cluster-wide secret read could use it.
The Job applies with `--mode no-reboot`, one node at a time, and waits for
the API server, the node, its control-plane pods and every Deployment to be
healthy before the next node.

Rules for a patch:

- One YAML document, a strategic-merge patch (a map). Talos refuses JSON patches
  for multi-document machine configs, which this cluster has.
- **It owns every list it mentions.** Strategic merge appends to lists, so the
  script applies each patch as set, clear, set: the clear copy deletes every
  list the patch mentions. Entries the patch does not list are removed from the
  node.
- A change that needs a reboot fails the job instead of rebooting. Reboots go
  through Talos upgrades.
- The plan prints only added and removed lines. Never print talosctl's dry-run
  diff in CI: its unchanged context includes private keys, and the repository's
  Actions logs are public.

Talos does not validate every value: on a test cluster it accepted
`podSubnets: [not-a-cidr]`, which crash-looped kube-controller-manager. Review
the plan's changed lines as carefully as the patch. After a change, the script
waits until the node's control-plane pods have stayed Ready without restarting
for 90 seconds, and fails the run if that does not happen within 15 minutes. It
cannot repair the node. A broken kube-controller-manager also stops the Jobs
this script depends on, so fix such a node by hand with `talosctl` over the tailnet
(Bootstrap below shows how to get the talosconfig), then fix the patch.

A change to the API server (`cluster.apiServer`) restarts it. Every controller
on the mgmt cluster then loses its leader lease and restarts, so the CAPI
admission webhooks are unavailable for about three minutes. The kubectl job runs
after the Talos job for that reason.

## Bootstrap (once per cluster)

CI can only take over after the node allows Talos API access from
`mgmt-talos`. Apply that patch by hand once, from a machine on the tailnet:

```bash
(umask 077; op document get "talosconfig: tuist-mgmt" --vault Development > /tmp/talosconfig)
TALOSCONFIG=/tmp/talosconfig talosctl -n 100.92.208.109 -e 100.92.208.109 patch machineconfig \
  --patch @infra/k8s/mgmt/talos/patches/10-talos-api-access.yaml
rm /tmp/talosconfig
```

## Previewing locally

`CI=1` keeps the repo's mise postinstall hook from running `tuist setup`.

```bash
HCLOUD_TOKEN=op://tuist-k8s-mgmt-hetzner/hetzner-tuist-mgmt/credential \
  CI=1 op run -- mise exec -- infra/mise/tasks/mgmt/reconcile-hetzner.sh
```

The Talos preview runs the same dry-run Job CI does (creating the
`mgmt-talos` namespace, ServiceAccount and patch ConfigMap if missing), so it
needs the mgmt kubeconfig (`kubeconfig: tuist-mgmt` in the `tuist-k8s-mgmt` vault):

```bash
KUBECONFIG=~/.kube/tuist-mgmt.yaml CI=1 mise exec -- infra/mise/tasks/mgmt/reconcile-talos.sh
```

## `patches/20-control-plane-resources.yaml`

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

Raise a limit if the component's working set gets close to it
(`container_memory_working_set_bytes{cluster="tuist-management", namespace="kube-system"}`).
Crossing it means a kernel OOM kill of that one container.
