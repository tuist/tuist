# Tuist ClusterClass + Cluster CRs

Self-hosted Kubernetes manifests for the Tuist workload clusters
(staging / canary / production / preview), reconciled by our own
management cluster running CAPI + caph. Production Kura regions are
dedicated node pools inside the production workload cluster.

## Why a ClusterClass

ClusterClass is CAPI's native templating layer. We author one
`ClusterClass` (`tuist-hcloud`) that defines the reusable shape — HA
control plane, worker-pool variables, network config,
`KubeadmControlPlaneTemplate`, `HCloudMachineTemplate` — and per-cluster
`Cluster` CRs reference it via `topology.classRef.name`, only specifying
what differs (replica counts, machine types per pool, labels, taints).
K8s minor bumps are a `topology.version:` edit on each Cluster CR.

## Layout

```
clusters/
├── README.md                  this file
├── clusterclass-tuist.yaml    the tuist-hcloud ClusterClass
├── cluster-staging.yaml       per-env Cluster CRs in topology mode
├── cluster-canary.yaml
├── cluster-production.yaml
└── cluster-preview.yaml
```

## Target shape per cluster

| Cluster | CP | Workers |
|---|---|---|
| `tuist-staging` | 3× cpx22 | md-0: 2× cpx32; md-egress: 2× cpx22 (`pool=egress`, HA stable-egress gateway); kura: 3× ccx13 (`pool=kura`, autoscaled 3→12); runners-linux: bare-metal Robot (`pool=runners-linux`) |
| `tuist-canary` | 3× cpx32 | md-0: 2× cpx32; md-egress: 2× cpx22 (`pool=egress`, HA stable-egress gateway); kura: 3× ccx13 (`pool=kura`); runners-linux: bare-metal Robot (`pool=runners-linux`) |
| `tuist` (production) | 3× cpx22 | md-0: 3× ccx23 (`pool=general`); md-egress: 2× cpx22 (`pool=egress`, HA stable-egress gateway); md-processor: 2× cpx62 (`pool=processor`, autoscaled 2→6); kura: 3× ccx13 (`pool=kura`, autoscaled 3→12); kura-us-east: 3× ccx13 in `ash` (`pool=kura-us-east`, autoscaled 3→32); kura-us-west: 3× ccx13 in `hil` (`pool=kura-us-west`, autoscaled 3→12); runners-linux: 2× AX162-R bare-metal Robot in `fsn1` (`pool=runners-linux`) |
| `tuist-preview` | 1× cpx22 | md-0: 1× cpx42 |

The `md-egress` pool is the HA (≥2 node) stable-egress gateway: the
production Phoenix server's public egress is SNAT'd through the active
node's Hetzner Floating IP, with the failover controller keeping the IP +
active label on one Ready candidate. It exists on staging/canary too so
the failover path is exercised down the deployment cascade before
production. See the pool comment in `cluster-production.yaml`.

Variables exposed by the ClusterClass: control plane replicas + machine
type, per-pool machine type, region (default `fsn1`), SSH key name,
optional Hetzner Cloud Network config, optional placement groups.

Managed Kura region mapping is:

| Product region | Cluster ID | CAPI Cluster | Hetzner location |
|---|---|---|---|
| `eu-central` | `eu-central-1` | `tuist` node pool `kura` | `fsn1` |
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
- [`coredns-config.yaml`](../mgmt/bootstrap/coredns-config.yaml) gives CoreDNS independent public Domain Name System resolvers from [Cloudflare](https://developers.cloudflare.com/1.1.1.1/) and [Google](https://developers.google.com/speed/public-dns/). This protects existing workers without causing an incident-time fleet rollout and keeps a CoreDNS reschedule from depending on host stub behavior.
- Worker kubelets still inherit the current resolver behavior. Adding `resolvConf` to their bootstrap configuration requires a separate, controlled rolling replacement. The explicit CoreDNS upstreams fix cluster name resolution without initiating that fleet change.
- When bumping `topology.version`, update the CoreDNS fork for the matching kubeadm and CoreDNS defaults, then verify internal and public name resolution through the canary, staging, and production cascade.
