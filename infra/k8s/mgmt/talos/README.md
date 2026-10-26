# Management node Talos patches and Hetzner resources

The management cluster runs on Talos control-plane nodes in Hetzner Cloud
project `tuist-mgmt`, listed under `nodes` in `hetzner.yaml`. Both of its layers
are reconciled on merge to main by `.github/workflows/mgmt-cluster-apply.yml`,
which prints the planned changes before applying them.

- `hetzner.yaml` declares the nodes' servers and the Hetzner resources around
  them: the private network (each node attached at its `privateIP`), a spread
  placement group, and the `tuist-mgmt-api` load balancer in front of the
  Kubernetes API with a primary IPv4 of the same name, so its address survives a
  load balancer recreate. The `hetzner` job applies it with
  `infra/mise/tasks/mgmt/reconcile-hetzner.sh`. The token lives in the
  `tuist-k8s-mgmt-hetzner` vault, which only that job's `mgmt-hetzner`
  environment can read.
- `patches/` holds Talos machine config patches for every control-plane node.
  The `talos` job joins new nodes and applies the patches with
  `infra/mise/tasks/mgmt/reconcile-talos.sh`, after the `hetzner` job has
  succeeded.

## Adding a control-plane node

Add the node to `nodes` in `hetzner.yaml` with the next free private IP, and a
`location` if it should not be in the top-level one (any location in the
network's eu-central zone works). On merge:

1. The `hetzner` job creates the server from the Talos snapshot in `server`,
   powered off, attaches it to the network at its private IP, and powers it on.
   It gets no user data, so Talos waits in maintenance mode.
2. The `talos` job checks that every etcd member votes, then runs a Job that
   copies an existing node's machine config to the new node over the private
   network. The config holds the cluster's private keys, so it is never passed
   as Hetzner user data (readable by every pod on the node) and never leaves the
   cluster. The node joins etcd as a learner and registers with Kubernetes.
3. The job waits until the node is Ready, checks DNS and pod HTTP in every
   direction between the control-plane nodes, then requires stable
   control-plane pods and a voting etcd member before joining the next node.
   It applies `patches/` to all nodes, synchronizes the live Flannel arguments,
   and checks private Flannel endpoints and pod networking again.

Add nodes in pairs, so etcd keeps an odd number of members: two members need
both to keep quorum, which tolerates no more failures than one. Removing a node
from `nodes` only removes its load balancer target. Take it out of etcd and
Kubernetes by hand first (`talosctl reset` over the tailnet).

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

Talos Jobs are pinned to an existing Ready control-plane member, also used as
the source of a new node's config. A new member's broken pod network is checked
by separate, credential-free probes rather than by scheduling the etcd query
on that member. The health gate requires all three static control-plane pods
and logs their UID, restart count and readiness when its stability window
resets. A stable but unready pod cannot satisfy the window.

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

## Private Flannel traffic

`patches/60-private-flannel.yaml` selects the interface used to reach Hetzner's
private gateway, `10.0.0.1`. It explicitly names the Flannel CNI: adding only
`flannel.extraArgs` to a config with the default CNI omitted fails validation.

The machine-config patch is necessary for future bootstrap, but does not
update an existing DaemonSet. Talos 1.13.0's
[manifest controller](https://github.com/siderolabs/talos/blob/v1.13.0/internal/app/machined/pkg/controllers/k8s/manifest_apply.go)
skips objects already in its inventory or already present in Kubernetes.
After all node patches succeed, `reconcile-flannel.sh --apply` uses server-side
apply to own only the `kube-flannel` container's arguments. The extra arguments
come from the Talos patch; the two base arguments match Talos's manifest. It
leaves the image, environment, mounts and security context with Talos.

The script waits for rollout, requires every declared node's
`flannel.alpha.coreos.com/public-ip` annotation to equal its `privateIP`, then
runs `check-pod-network.sh`. The latter starts a temporary HTTP pod on each
control-plane node and a client Job on each node. Every client must resolve
`kubernetes.default.svc.cluster.local` and read the expected node identity from
every server pod IP. This exercises both directions across each node pair,
not just host networking or local pod traffic. Probes have no API token, run
under the restricted Pod Security policy, have deadlines, and are deleted on
exit. A failed check stops the Talos job before any further join.

Changing the VXLAN interface briefly interrupts cross-node pod traffic while
the DaemonSet rolls and peer endpoints converge. Keep the temporary public
VXLAN firewall rule until the complete migration and network gate pass.
The `hetzner` job precedes `talos`, so removing that rule there in the same
rollout would close the working path too early.

### Operator rollout and remaining HA work

The 2026-10-26 read-only check confirmed three Ready control-plane nodes,
public Flannel endpoints and three healthy public API load-balancer targets.
This change prepares the next rollout; local testing does not change that
live state. Production mutations remain operator-run as specified in the
handoff.

1. Apply the reviewed Talos changes through the normal main-branch workflow.
   Require private endpoint verification and the complete pod-network gate.
   The workload step restores caph to two replicas and applies
   `../controller-pdbs.yaml`, keeping at least one ready replica of each of the
   six admission webhooks during voluntary eviction. Check both replicas and
   `kubectl get pdb -A` before draining anything. Budgets do not protect against
   node failures or direct Deployment rollouts.
2. After the network gate passes, remove the temporary **UDP 8472 and UDP
   4789** ingress rules from firewall `tuist-mgmt`, preserving the TCP API
   rule and every unrelated rule. Re-run `check-pod-network.sh` afterwards.
   Inspect the live rules with `hcloud firewall describe tuist-mgmt -o json`
   and use their exact direction, protocol, port and source IPs when calling
   `hcloud firewall delete-rule`. Firewall ownership is not yet declarative.
3. In a subsequent rollout, set `loadBalancer.usePrivateIP: true`. The
   reconciler reads fresh target health immediately before removing a target,
   requires a different target healthy on every configured API port, and
   waits up to five minutes for the switched target to recover before moving
   on. A missing/unknown check is not healthy. If a switch fails, it stops
   with the other targets in place; repair or revert that target before
   retrying. After every private target is healthy and API writes through the
   load balancer work, remove the nodes' public TCP 6443 firewall rule.
4. Upgrade Talos from 1.13.0 to 1.13.11 one node at a time only after a current
   etcd snapshot is verified and the webhook budgets/replicas are healthy.
   Confirm the installed image's architecture and extension schematic before
   choosing the installer. For each node, wait for Ready, all voting etcd
   members, stable control-plane pods, private Flannel endpoints, the complete
   pod-network gate and a healthy load-balancer target before the next node.
   The upgrade and installer/snapshot selection are deliberately separate
   from this network migration.
5. Remove the old Tailscale rollback Secrets only after verifying their exact
   names and lack of references. Migrate the etcd snapshot credential to the
   ephemeral Talos ServiceAccount approach separately; it is still pinned to
   the first node. Check that node's advertised etcd client URL after its
   rolling restart. The original ten-minute join delay remains unexplained:
   the current pod timestamps do not identify why earlier pods were replaced.
   Use the stability-window reset logs on the next join rather than reducing
   the safety window.

If the Flannel migration fails, retain the public VXLAN exception. Restore
the old DaemonSet arguments (`--ip-masq`, `--kube-subnet-mgr`) and roll it back
to the working public path before retrying; revert the Talos extra arguments
too so a later bootstrap does not reintroduce the failed selection. Do not
remove firewall rules or begin an OS upgrade while the network gate fails.

### Validation

Credential-free checks run in `mgmt-cluster-tests.yml`:

```bash
CI=1 mise exec -- infra/mise/tasks/mgmt/test-health.sh
CI=1 mise exec -- node --test infra/mise/tasks/mgmt/test-hetzner.cjs
CI=1 mise exec -- shellcheck infra/mise/tasks/mgmt/{test-health,check-pod-network,reconcile-flannel,reconcile-talos,reconcile-hetzner}.sh
CI=1 mise exec -- actionlint .github/workflows/mgmt-cluster-{apply,tests}.yml
```

For integration testing, use an isolated Docker Talos 1.13.0 / Kubernetes
1.36.5 cluster with two nodes and a second Docker network (`10.0.0.0/16`,
gateway `10.0.0.1`). Attach its nodes at `10.0.1.11` and `10.0.1.12`. With a
control-plane/worker test cluster, label the disposable worker
`node-role.kubernetes.io/control-plane` so both participate in the probe;
this tests pod networking, not multi-member etcd. Keep its kubeconfig and
Talos credentials under gitignored `tmp/` and select that kubeconfig explicitly.
`MGMT_TALOS_SPEC` can point `reconcile-flannel.sh` at a temporary spec containing
the test node names/private IPs; the production default remains `hetzner.yaml`.

The local test on 2026-10-26 applied the patch without rebooting, switched both
Flannel annotations to the private addresses, passed DNS and HTTP in both
directions, failed the gate after disconnecting one private Docker interface,
and passed again after reconnection and a Flannel restart. A repeat reconciliation
passed without changing the DaemonSet generation. All six PDB manifests passed
server-side dry-run validation against that local Kubernetes API. Docker has no
Hetzner firewall, so this does not validate live firewall removal, load-balancer
switching or an OS upgrade.
