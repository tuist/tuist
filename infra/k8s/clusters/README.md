# Tuist ClusterClass + Cluster CRs

Self-hosted Kubernetes manifests for the Tuist workload clusters
(staging / canary / production), reconciled by our own
management cluster running CAPI + caph. Production Kura regions are
dedicated node pools inside the production workload cluster.

## Why a ClusterClass

ClusterClass is CAPI's native templating layer. We author one
`ClusterClass` (`tuist-hcloud`) that defines the reusable shape — HA
control plane, worker-pool variables, network config,
`KubeadmControlPlaneTemplate`, `HCloudMachineTemplate` — and per-cluster
`Cluster` CRs reference it via `topology.classRef.name`, only specifying
what differs (replica counts, machine types per pool, labels, taints).
K8s minor bumps are a `topology.version:` edit on each Cluster CR, one
cluster at a time. The ClusterClass pins `KUBERNETES_VERSION` for apt; a
Cluster ahead of the pin gets its packages from the
`*KubernetesPackages` patches. Once every Cluster has moved, move the pin
and both patches' `enabledIf` versions together (that rolls each cluster
once). Annotate a MachineDeployment topology with
`topology.cluster.x-k8s.io/defer-upgrade: ""` to keep it on the older
kubelet. The bare-metal `stateful-worker` pools need that: their templates
install from a fixed `pkgs.k8s.io` channel, and rolling them reinstalls the
box under ClickHouse.

## Layout

```
clusters/
├── README.md                  this file
├── clusterclass-tuist.yaml    the tuist-hcloud ClusterClass  (mgmt-cluster-apply.yml)
├── bare-metal.yaml            runner substrate: bare-metal-worker class
│                              (Kata, whole-disk root)        (mgmt-cluster-apply.yml)
├── bare-metal-stateful.yaml   stateful substrate: stateful-worker class
│                              (separate /data, no Kata, per-cluster RAID;
│                              carries ClickHouse)            (mgmt-cluster-apply.yml)
├── machinedrainrules.yaml     per-workload drain behaviour   (mgmt-cluster-apply.yml)
└── workloads/                 Flux-reconciled Cluster CRs (infra/flux/mgmt/)
    ├── staging/{cluster,kustomization}.yaml
    ├── canary/{cluster,kustomization}.yaml
    ├── production/{cluster,kustomization}.yaml
    ├── hive/{cluster,kustomization}.yaml    tenant (migrated from tuist/hive)
    ├── once/{cluster,kustomization}.yaml    tenant (migrated from tuist/once)
    └── atlas/{cluster,kustomization}.yaml   tenant (migrated from tuist/atlas)
```

## Reconciliation ownership

Two mechanisms apply these manifests, split deliberately (see
[hive/specs/72](https://hive.tuist.dev/specs/72) and `infra/flux/mgmt/README.md`):

- **Flux** (`infra/flux/mgmt/`) continuously reconciles the per-cluster
  `Cluster` CRs under `workloads/`, one Flux `Kustomization` per subdir,
  scoped never to prune a `Cluster` object. This is the source of truth
  for the staging / canary / production and hive / once / atlas topologies.
- **`mgmt-cluster-apply.yml`** keeps everything else at the flat `clusters/`
  path: the immutable `clusterclass-tuist.yaml` and `bare-metal*.yaml`
  templates (whose delete-and-apply fallback for `field is immutable` a plain
  Kustomization can't reproduce — a new `bare-metal*.yaml` is picked up by its
  glob without touching the workflow) and `machinedrainrules.yaml`.
  Flux never sees these files.

Tenant `Cluster` CRs were migrated in from `tuist/{hive,once,atlas}`
(`infra/k8s/cluster-production.yaml`). Keep each `workloads/<tenant>/cluster.yaml`
byte-identical to the live object so the first Flux reconcile is a no-op;
the tenant-repo copies are then retired to a pointer.

## Target shape per cluster

| Cluster | CP | Workers |
|---|---|---|
| `tuist-staging` | 3× cpx22 | md-0: 2× cpx32; md-egress: 2× cpx22 (`pool=egress`, HA stable-egress gateway); md-clickhouse: 1× AX42-1 in `fsn1` (`pool=clickhouse`, `stateful-worker`); kura: 3× ccx13 (`pool=kura`, autoscaled 3→12); runners-linux: 1× OVH RISE-S in `gra` (`pool=runners-linux`) |
| `tuist-canary` | 3× cpx22 | md-0: 4× cpx32; md-egress: 2× cpx22 (`pool=egress`, HA stable-egress gateway); kura: 3× ccx13 (`pool=kura`); runners-linux: 1× OVH RISE-S in `gra` (`pool=runners-linux`) |
| `tuist` (production) | 3× cpx32 | md-0: 5× ccx23 (`pool=general`); md-egress: 2× cpx22 (`pool=egress`, HA stable-egress gateway); md-processor: 2× cpx62 (`pool=processor`, autoscaled 2→6); kura: 3× ccx13 (`pool=kura`, autoscaled 3→12); kura-us-east: 3× ccx13 in `ash` (`pool=kura-us-east`, autoscaled 3→32); kura-us-west: 3× ccx13 in `hil` (`pool=kura-us-west`, autoscaled 3→12); runners-linux: 6× OVH RISE-L in `gra` (`pool=runners-linux`) |

Canary's general-purpose pool runs its three CNPG instances and reserves
capacity for deployment hooks and rolling-update surge pods. Without that
headroom the 512Mi ClickHouse schema-clone hook stays unschedulable until Helm
times out and rolls back. After
changing this pool, wait for Flux to reconcile and the new worker to become
Ready before retrying the deployment.

`tuist-pentest`, the fixed-duration security-assessment cluster, is retired.
Its manifest is removed; the **Pentest Cluster Retirement** workflow deletes
the Cluster resource, its managed infrastructure and its ingress load balancer.
Before running it, delete every DNS record pointing at the cluster's load
balancers: the run frees their IPs, and a reassigned IP would take over the
hostname (see `../onboarding.md` §9).

The `md-egress` pool is the HA (≥2 node) stable-egress gateway: the
production Phoenix server's public egress is SNAT'd through the active
node's Hetzner Floating IP, with the failover controller keeping the IP +
active label on one Ready candidate. It exists on staging/canary too so
the failover path is exercised down the deployment cascade before
production. See the pool comment in `cluster-production.yaml`.

## Worker health checks

Each MachineDeployment class in the ClusterClass defines a
`MachineHealthCheck`: Ready `Unknown` or `False` for 5 minutes on cloud
workers, and 10 minutes on bare metal, where remediation stays disabled. A
pool's `healthCheck` in a Cluster CR replaces the class block entirely, not
field by field. If an override sets only `remediation`, the pool gets no
unhealthy node conditions and only the default startup timeout. Overrides
must restate `checks`.

Cloud workers remediate one unhealthy node at a time (`unhealthyInRange:
"[0-1]"`). When two nodes in a pool are unhealthy at once, CAPI holds, and the
"Worker node pool below desired replicas" alert pages after 15 minutes.

`nodeLockupHardening` is an opt-in worker variable that applies the kernel
lockup panics and systemd watchdog from `cluster-api-provider-tuist` to cloud
workers. Changing it rolls the pool, so set it as a MachineDeployment override
one pool at a time.

These nodes get `net.mptcp.enabled = 0` (Multipath TCP off) from the platform
chart's `disableMultipathTCP` DaemonSet, not from the templates here: changing a
ClusterClass template rolls every pool that uses it. A node that joins later gets
the value when that pod starts, so the listeners its kubelet and Cilium opened
before then stay MPTCP until they restart.

Variables exposed by the ClusterClass: control plane replicas + machine
type, per-pool machine type, region (default `fsn1`), SSH key name,
optional Hetzner Cloud Network config, optional placement groups.

Managed Kura region mapping is:

| Product region | Cluster ID | CAPI Cluster | Hetzner location |
|---|---|---|---|
| `eu-west` | `eu-west-1` | `tuist` node pool `kura-dedibox` | OVHcloud, Gravelines |
| `us-east` | `us-east-1` | `tuist` node pool `kura-us-east` | `ash` |
| `us-west` | `us-west-1` | `tuist` node pool `kura-us-west` | `hil` |

## Image strategy

Hetzner-published Ubuntu images plus cloud-init that installs containerd
+ runc + kubelet at first boot (~2–3 min cold start). Simple to reason
about; no Packer pipeline. Acceptable for the autoscaler's `md-processor`
2→6 cadence; if scaling latency becomes painful we can introduce a
pre-baked image without changing the ClusterClass shape.

## Replacing a production runner node

Production runner-node replacement is not automated. The fleet has
exactly two pre-ordered physical hosts, so the current MachineDeployment
cannot create a current-revision replacement before releasing an old
node. Deleting an individual Machine can also let its outdated
MachineSet recreate the old revision.

Do not delete a claimed `HetznerBareMetalHost` or remove its finalizers.
The safe prerequisite is a third pre-ordered production runner host and
a matching replica increase. That gives the MachineDeployment spare
capacity to create and verify a current-revision node before an old node
is drained.

## Upgrading the ClickHouse pool in place

The `stateful-worker` class (`md-clickhouse`) is `OnDelete`. A new
`topology.version` moves the MachineDeployment's template and replaces no
Machine. Replacing a box would reinstall it, wiping `/data` and with it that
ClickHouse replica, and would change its node name, which
`clickhouse.managed.persistence.localVolume.nodeNames` pins the replica to.
Each Kubernetes minor is therefore applied to the boxes in place, one box at
a time.

CAPI's Cluster webhook refuses the next `topology.version` bump until every
Machine's `spec.version` matches its MachineDeployment
(`validateTopologyMachineDeploymentVersions`). It reads `spec.version` and
never the kubelet, and `spec.version` is mutable. So the procedure ends by
recording the new version on each Machine. The Machines stay owned by their
old MachineSet and show as not up to date, which `OnDelete` leaves alone. A
box that is reprovisioned later joins at the template's version anyway.

Everything below the PR is a human operation:
- On canary and production it needs an elevation covering cordon, drain
  and `kubectl debug node`, or root SSH to the box.
- The Machine patch needs write access to the management cluster.

1. Merge the Cluster CR change: drop `topology.cluster.x-k8s.io/defer-upgrade`
   from `md-clickhouse`, or bump `topology.version` with the pool following
   it. Wait for Flux to apply it. The MachineDeployment's
   `spec.template.spec.version` then reads the new version, and no Machine
   is replaced.
2. Check both replicas are healthy first. All `tuist-tuist-clickhouse-*` pods
   must be Ready: Ready means `/replicas_status` reports the replica caught
   up. The PodDisruptionBudget refuses the drain otherwise, and that refusal
   is the point. Check that the last backup CronJob runs succeeded.

   Then check that no backup is running. Don't drain either box while one
   is, including the box whose replica isn't running it. Backups run at
   01:00 UTC: the weekly full on Mondays takes about 11 hours on production,
   and the daily incremental takes much less. On production on 2026-11-09,
   draining `clickhouse-1`'s box failed the full that `clickhouse-0` had
   been writing for 7 hours. It failed with an S3 `RequestCanceled` 21
   seconds after the eviction, and the Job's one retry then started again
   from scratch. Before draining, both of these must be empty:

   ```bash
   kubectl -n <namespace> get jobs | grep clickhouse-backup | grep Running
   kubectl -n <namespace> exec tuist-tuist-clickhouse-0 -c clickhouse -- \
     sh -c 'clickhouse-client --password "$TUIST_CLICKHOUSE_PASSWORD" \
       -q "SELECT name, start_time FROM system.backups WHERE status = '\''CREATING_BACKUP'\''"'
   ```

   Repeat the `system.backups` query on `tuist-tuist-clickhouse-1`. The
   server can keep writing a backup after its Job has failed or hit its
   deadline. That's why `system.backups` is the check, not the Job's status.
3. For **one** box (`NODE=bm-...-md-clickhouse-...`):

   ```bash
   kubectl cordon "$NODE"
   kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --timeout=15m
   # ClickHouse stops; its local PV stays on disk.
   kubectl debug node/"$NODE" -it --profile=sysadmin --image=ubuntu:24.04 \
     -- nsenter --target 1 --mount --uts --ipc --net --pid -- bash
   ```

   On the host, first run `dpkg --audit`. A half-configured unrelated package
   makes every `apt-get install` exit 100 even when the requested packages
   install. We saw this with `openssh-server` after unattended-upgrades,
   because its postinst can't start `ssh.socket` while the boot-time sshd
   holds :22. Leave that package alone, and check the result with
   `dpkg -l kubeadm kubelet kubectl` (`ii` or `hi`) instead of apt's exit code.

   Then, with `V` the control plane's patch version (for example `1.35.10`):

   ```bash
   V=1.35.10; MINOR=${V%.*}
   cp -a /var/lib/kubelet/config.yaml /var/lib/kubelet/kubeadm-flags.env /root/
   curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$MINOR/deb/Release.key" \
     | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$MINOR/deb/ /" \
     > /etc/apt/sources.list.d/kubernetes.list
   apt-get update
   apt-mark unhold kubelet kubeadm kubectl
   apt-get install -y kubeadm="$V-*"
   kubeadm upgrade node
   apt-get install -y kubelet="$V-*" kubectl="$V-*"
   apt-mark hold kubelet kubeadm kubectl
   # The reservations and eviction thresholds are flags in kubeadm-flags.env;
   # both files should come back unchanged apart from version-specific defaults.
   # On 1.35, kubeadm drops --pod-infra-container-image (kubelet 1.35 rejects it).
   diff /root/kubeadm-flags.env /var/lib/kubelet/kubeadm-flags.env
   diff /root/config.yaml /var/lib/kubelet/config.yaml
   dpkg -l kubeadm kubelet kubectl
   systemctl daemon-reload
   # The debug shell's exec stream runs through this kubelet, so a direct
   # restart cuts it mid-command. Restart a few seconds after returning.
   systemd-run --on-active=3 --unit=tuist-kubelet-restart systemctl restart kubelet
   ```

   Expected noise: `kubeadm upgrade node` warns that it can't read the
   `kube-proxy` ConfigMap, because the node identity has no access to it.
   The node keeps the `node.cluster.x-k8s.io/outdated-revision:PreferNoSchedule`
   taint, because its Machine stays on the old MachineSet. The kubelet log's
   "Nameserver limits exceeded" errors predate the upgrade.

   Exit the debug shell, delete the debug pod (`kubectl get pods | grep node-debugger`),
   and then:

   ```bash
   kubectl get node "$NODE" -o jsonpath='{.status.nodeInfo.kubeletVersion}'  # v1.35.10
   kubectl uncordon "$NODE"
   ```

   Wait for that ClickHouse pod to be Ready again. It restarts on its own
   data and only catches up on the writes it missed. Before the next box,
   check in both pods (`clickhouse-client --password "$TUIST_CLICKHOUSE_PASSWORD"`):
   - In `system.replicas`, no table is `is_readonly`, `absolute_delay` is 0
     and `active_replicas` equals `total_replicas`.
   - `system.replication_queue` has no entries with `last_exception`.
   - Per-table `sum(rows)` over active `system.parts` agrees between the two
     pods. Small gaps from live inserts close within a minute.
     `last_queue_update_exception` keeps the last Keeper error after
     recovery, so a stale value there is not a failure.
4. Repeat step 3 for the other box. Never start it before the first replica
   is Ready.
5. On the management cluster, record the version on both Machines. Without
   `KUBECONFIG`, kubectl falls back to `localhost:8080`:

   ```bash
   export KUBECONFIG=$(mktemp)
   op document get "kubeconfig: tuist-mgmt" --vault tuist-k8s-mgmt > "$KUBECONFIG"
   for m in $(kubectl -n org-tuist get machines \
       -l cluster.x-k8s.io/cluster-name=<cluster>,topology.cluster.x-k8s.io/deployment-name=md-clickhouse -o name); do
     kubectl -n org-tuist patch "$m" --type merge -p '{"spec":{"version":"v1.35.10"}}'
   done
   rm -f "$KUBECONFIG"; unset KUBECONFIG
   ```

   The next `topology.version` bump is then accepted.

## Resizing the control plane

`hcloudControlPlaneMachineType` is patched into the control-plane
`HCloudMachineTemplate`, so changing it makes the topology controller
create a new template and roll the `KubeadmControlPlane`. KCP uses its
default rolling update (`maxSurge: 1`): it adds a fourth member on the new
type, which joins etcd as a learner and is promoted to a voter, then removes
one old member. It repeats that three times. Each step replaces a Hetzner
server, so the control-plane nodes get new names and public IPs.

Merging a change under `workloads/` is the apply: Flux polls the repository
every minute, so the roll starts about a minute after merge. Before merging:

- If the CAPI or caph controllers changed since the last control-plane roll,
  rehearse with a same-type roll on staging (set the staging KCP's
  `spec.rollout.after` to now) rather than resizing staging. Check the field
  with `kubectl explain kcp.spec.rollout.after` (older APIs use
  `spec.rolloutAfter`), and confirm a new control-plane Machine appears;
  if none does, nothing rolled.
- Confirm etcd has three healthy voters (`etcdctl endpoint status --cluster`
  in an etcd pod, which needs `/elevate` for `pods/exec`; without it,
  `etcd_server_has_leader` is 1 on every member, leader changes are flat, and
  WAL fsync p99 is normal) and the KCP reports three up-to-date, Ready
  replicas.
- Check the fleet for host rules that pin the API endpoint to one member.
  The roll gives every member a new server, and a member's IP is not always
  reused, so a node whose host NATs the load balancer address to a single
  member loses the API when that member is removed. On 2026-10-07 a
  redirect left over from an incident took the EU East Kura node down this
  way (see `infra/kura-controller/incidents/2026-09-22-eu-east.md`). On
  each Linux fleet host, `sudo iptables -t nat -S OUTPUT` must show nothing
  that matches the load balancer address or a control-plane member's IP.
  During the roll, a worker that goes NotReady right after a member is
  deleted points to such a pin.
- Pick an off-peak window with no server deploy running or queued.
- Silence `Hetzner control-plane load-balancer target unhealthy` for the
  window: each new member is a load-balancer target for several minutes
  before its apiserver answers. The Flux `Kustomization` also times out
  (15 minutes) before the roll finishes. Neither is a failure signal.

The control-plane `MachineHealthCheck` never remediates a member that fails
to register a Node (`nodeStartupTimeoutSeconds: 0`), so a stuck join halts
the roll with the old members still serving. Deleting the stuck Machine also
deletes its server, and KCP immediately creates a replacement, so pause first:
annotate the `KubeadmControlPlane` with `cluster.x-k8s.io/paused` and diagnose
on the stuck host. Pause only the KCP, not the `Cluster`: pausing the Cluster
also stops every worker pool from scaling or remediating. Then remove the
annotation and either delete the stuck Machine (KCP retries) or revert.
Reverting the type is another full roll, not an undo.

## Adapting from caph upstream

`clusterclass-tuist.yaml` was originally forked from caph's
`cluster-class.yaml` release asset. To diff against a new caph release:

```bash
gh release download <tag> --repo syself/cluster-api-provider-hetzner \
  --pattern 'cluster-class*.yaml' --pattern 'cluster-template-hcloud*.yaml'
```

Adaptations to be aware of when porting upstream changes:

- Bare-metal `MachineDeployment` class + bare-metal templates dropped (we only run cloud servers).
- All 5 resources scoped to the `org-tuist` namespace (otherwise `topology.classRef` lookup fails because Cluster CRs live in `org-tuist`).
- `initConfiguration.skipPhases: [addon/kube-proxy]` on the KCP because Cilium replaces kube-proxy.
- `hcloudPlacementGroups` variable defaults to `[]` (otherwise the patch errors at render time).
- `hcloudControlPlanePlacementGroupName` and `hcloudWorkerMachinePlacementGroupName` patches split into separate `enabledIf` definitions: caph rejects empty-string `placementGroupName` with "Placement group does not exist", so we only emit the patch when the variable is non-empty.
- `KUBERNETES_VERSION` and `CONTAINERD` in `preKubeadmCommands` ported from the flat `cluster-template-hcloud.yaml`. The reference ClusterClass uses an old `cri-containerd-cni-` bundle that's no longer published for containerd 2.x.
- `containerd.service` systemd unit added to both KCP and worker `files:` blocks. The plain `containerd-` tarball doesn't ship one (only the older `cri-containerd-cni-` bundle did). Without this, `systemctl start containerd` finds no unit and PLEG never goes healthy.
- `containerRuntimeEndpoint`, `staticPodPath`, `cgroupDriver`, `clusterDNS`, `clusterDomain`, **`authentication.x509.clientCAFile`** added to the kubelet `KubeletConfiguration` shipped via the `files:` block. Critical: kubelet is invoked with two `--config` flags (kubeadm's default + ours via `kubeletExtraArgs`) and the second OVERRIDES the first, so any field omitted here gets cleared. Without `clientCAFile`, kubelet rejects the kube-apiserver's client cert as Unauthorized → `kubectl exec`, `kubectl port-forward`, and KCP's etcd health check all fail; KCP then refuses to scale the control plane to 3 replicas.
- Control-plane kubelets set `resolvConf` to `/run/systemd/resolve/resolv.conf`. Ubuntu's `/etc/resolv.conf` points at the host-local `127.0.0.53` stub, which is unreachable from pod network namespaces.
- Control-plane Machine deletion retries Kubernetes Node removal indefinitely. The default ten-second deletion window can expire during a brief control-plane interruption and leave an unreachable Node after its Machine and server are gone. The ClusterClass control-plane deletion policy propagates this in place, so changing the immutable control-plane template is unnecessary.
- All kubelets use `/run/systemd/resolve/resolv.conf` for resolver configuration. Ubuntu's `/etc/resolv.conf` points at a host-local `127.0.0.53` stub, which is unreachable from pod network namespaces. Cloud-worker MachineDeployments use an explicit rolling strategy that keeps all desired workers available and creates at most one additional worker per pool during this configuration change.
- CoreDNS remains kubeadm-owned. Do not fork or reconcile its ConfigMap: [kubeadm does not support persisting CoreDNS ConfigMap customizations](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags/#customizing-coredns).
