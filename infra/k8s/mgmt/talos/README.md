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

Operators reach the Talos API over the tailnet, and CI stays off it. Instead,
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

A change to the API server (`cluster.apiServer`) restarts it on that node.
In the three-member cluster, healthy sibling API targets and webhook replicas
should preserve availability. Controllers can still retry or restart during the
transition; the per-node health gate must pass before the next member is patched.
The kubectl job runs after the Talos job.

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

### Verified HA state — 2026-10-27

All three control-plane nodes run Talos **1.13.11**, Kubernetes **1.36.5**
and etcd **3.6.14**. The final rolling-upgrade checks confirmed three voting
members with synchronized Raft indexes, private peer/client URLs, Ready nodes,
90 seconds of stable control-plane pods, all Deployments available, six webhook
PDBs allowing one disruption, and all seven workload Clusters Available.
DNS and pod HTTP passed in every direction after each node upgrade.

| Node | Private IP | Talos tailnet endpoint | Location |
| --- | --- | --- | --- |
| tuist-mgmt | 10.0.1.11 | 100.92.208.109 | fsn1 |
| tuist-mgmt-2 | 10.0.1.12 | 100.116.204.45 | nbg1 |
| tuist-mgmt-3 | 10.0.1.13 | 100.110.48.87 | nbg1 |

Flannel uses these private IPs. All three targets of API load balancer
`tuist-mgmt-api` are private and healthy; its public endpoint remains
`https://49.12.66.91:6443`. The public node TCP 6443 and temporary UDP 8472/4789
firewall rules were removed after verification. The firewall has no public
ingress rules. Do not restore public VXLAN as a routine troubleshooting step.

This records the completed live migration, not the deployment status of the
backup and provisioning follow-ups below. Production mutations remain
operator-run; repository changes deploy after review and merge to main.

### Rolling Talos upgrades and identity recovery

Before each node: verify a fresh etcd snapshot upload, all three voting members,
healthy private API targets, Ready control-plane pods stable for 90 seconds,
webhook replicas/PDBs and the pod-network gate. Upgrade exactly one node and
repeat these checks before continuing. Never bypass a failed health check with
`--force`.

The verified amd64 installer for the current empty-extension schematic is:

`factory.talos.dev/hcloud-installer/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba:v1.13.11`

Use **hcloud-installer**, retaining the installed architecture and schematic.
The generic `installer` variant changed node 2 to the metal platform during
this migration, and it registered as `talos-sif-xr2`. Reapplying the hcloud
installer restored its platform and original Kubernetes identity. A subsequent
drained reboot refreshed the old etcd member name; the member ID and data were
preserved throughout. Never remove that live etcd member to fix a stale name.
The obsolete Kubernetes Node was removed only after matching its system UUID
to the restored Ready node and verifying that only pending DaemonSet pods remained.

For this 1.13.0 → 1.13.11 migration we used `upgrade --legacy --preserve
--drain --drain-timeout=10m --wait --timeout=30m`. The legacy path avoided the
new upgrader's handling of existing GRUB kernel arguments; do not carry these
flags into a future major upgrade without reviewing that release's guidance.
Reach the node through a different healthy member's Talos endpoint (for example,
node 2's tailnet IP while rebooting node 1). Wait for the expected original
Kubernetes name, inspect PlatformMetadata/HostnameStatus and etcd membership,
and uncordon if needed. Never print machine configs or dry-run diffs, even filtered.

An upgrade initially failed because node 1 still advertised its old public
etcd **client** URL, despite private peer URLs and healthy Raft replication.
Talos validates every advertised client URL before an upgrade. A controlled
`reboot --drain --drain-timeout=10m --wait --timeout=20m` refreshed it after
confirming the resolved EtcdSpec had private addresses. `service etcd restart`
is not supported by Talos's service API. Do not disable validation or remove an
etcd member to work around this failure.

The original roughly ten-minute join delay remains unexplained. Observed
scheduler/controller-manager startup retries during these reboots included local
API TLS timeouts, but that does not establish the earlier join delay's cause.
Keep the 90-second stability gate and collect its reset timestamps on future joins.

### Backup credential rollout and verification

`../etcd-snapshot.yaml` now declares a Talos ServiceAccount named
`mgmt-system/etcd-snapshot`, with only `os:etcd:backup`. Talos issues a six-hour
certificate and renews it when less than one hour remains. Its generated Secret
contains a `config` key and uses `talos.default`, the in-cluster API Service.
The pod passes its own host IP as the target node and can schedule on any
control-plane member. It uses neither host networking nor a Kubernetes API token.

This is an automatically rotated, short-lived credential, **not** a Secret that
exists only during each Job. Keeping the native Talos controller responsible for
rotation avoids giving backup pods Kubernetes permission to create identities or
read/delete Secrets. The patcher's separate admin credential remains ephemeral.
The machine allowlist of roles and namespaces is global, not a per-namespace role
binding: preserve Kubernetes RBAC restrictions on creating Talos ServiceAccounts.
Deleting a Secret does not revoke an already copied certificate.

The workflow applies the API-access patch to all nodes before applying the new
ServiceAccount and CronJob. Keep `talos-snapshotter-config` until real uploads
succeed from every node. After the main-branch deployment succeeds, run:

```bash
KUBECONFIG=~/.kube/tuist-mgmt.yaml CI=1 mise exec -- \
  infra/mise/tasks/mgmt/verify-etcd-snapshot.sh --delete-legacy-credential
```

This copies the deployed Job template, pins one verification Job to each Ready
control-plane node in turn, and requires both snapshot and Tigris upload to finish.
It deletes the superseded credential only after all succeed; verification Jobs
remain for 24 hours. Failure leaves the old Secret intact. For rollback before
cleanup, restore the old CronJob spec from git; retain the new allowed namespace
until no new jobs use it. After cleanup, rollback also requires reissuing a backup
credential; prefer fixing the new path instead of restoring a long-lived key.

Snapshots are highly sensitive cluster data. Recovery is a separate disaster
operation requiring a cluster recovery plan and a verified downloaded snapshot.
Talos 1.13 exposes `talosctl bootstrap --recover-from=<snapshot>`; inspect
`talosctl bootstrap --help` for the deployed version before planning recovery.
Do not run this on a healthy cluster. The local integration check verifies
snapshot creation and upload, not a disaster restore.

### Obsolete Tailscale Secrets

Read-only checks on 2026-10-27 found no Tailscale workload or reference in
`mgmt-system`, and the active DaemonSet in `mgmt-tailscale` was 3/3 Ready.
The old `mgmt-system/tailscale-oauth` and `tailscale-state` are rollback copies.
`mgmt-tailscale/tailscale-state-talos-sif-xr2` belongs to the removed temporary
node identity, not to the restored node 2.

```bash
KUBECONFIG=~/.kube/tuist-mgmt.yaml CI=1 mise exec -- \
  infra/mise/tasks/mgmt/cleanup-ha-secrets.sh
KUBECONFIG=~/.kube/tuist-mgmt.yaml CI=1 mise exec -- \
  infra/mise/tasks/mgmt/cleanup-ha-secrets.sh --apply
```

The script rechecks Ready nodes, the complete DaemonSet rollout, active Secret
names, the missing temporary Node and workload/RBAC references before deleting
only those three names. It never reads Secret values. Active per-node state and
OAuth credentials stay in `mgmt-tailscale`. Removing rollback copies means the
old Deployment cannot be restored merely by reapplying its manifest. This does
not revoke an abandoned device in Tailscale's control plane.

### Provisioning future nodes

`hetzner.yaml` selects the clean `talos-v1.13.11` snapshot for new servers;
changing this field does not rebuild or upgrade existing servers. Upload it to
the **management** Hetzner project before adding a node. Never snapshot a joined
control-plane node for provisioning: that would copy cluster credentials and etcd
data into the image. Use the Image Factory's unconfigured hcloud disk image:

```bash
op signin --account tuist.1password.com &&
HCLOUD_TOKEN=op://tuist-k8s-mgmt-hetzner/hetzner-tuist-mgmt/credential \
  CI=1 mise exec -- op run -- "$HOME/.local/bin/hcloud-upload-image" upload \
    --image-url https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.13.11/hcloud-amd64.raw.xz \
    --architecture x86 --compression xz --location nbg1 \
    --description talos-v1.13.11 \
    --labels purpose=mgmt-cluster,talos-version=v1.13.11
```

This uses the verified local `hcloud-upload-image` 1.3.0 CLI. It creates a temporary
server, writes the clean disk image in rescue mode, snapshots it and deletes the
server. Verify exactly one available x86 snapshot with that description afterwards;
keep the 1.13.0 image until the new image has been verified. The reconciler refuses
new-server creation if the desired image is missing or ambiguous.

### Validation

Credential-free checks run in `mgmt-cluster-tests.yml`:

```bash
CI=1 mise exec -- infra/mise/tasks/mgmt/test-health.sh
CI=1 mise exec -- node --test infra/mise/tasks/mgmt/test-{hetzner,ha-followups}.cjs
CI=1 mise exec -- shellcheck infra/mise/tasks/mgmt/{test-health,check-pod-network,reconcile-flannel,reconcile-talos,reconcile-hetzner,cleanup-ha-secrets,verify-etcd-snapshot}.sh
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

The 2026-10-27 backup test used a separate local Talos 1.13.11 / Kubernetes
1.36.5 cluster. It enforced restricted Pod Security, issued a six-hour
`os:etcd:backup` certificate, created and integrity-checked an etcd snapshot,
and uploaded its complete contents with the production AWS CLI image to a local
S3 test endpoint using dummy credentials. Privileged service inspection was
denied. The operator verification script also completed a real local snapshot
and upload before deleting a dummy legacy Secret. This validates neither Tigris
credentials nor multi-node failover; the main-branch per-node verification gate
covers the live upload path. Always set `KUBECONFIG` to a temporary path before
`talosctl cluster create`, which otherwise merges into the default kubeconfig.
