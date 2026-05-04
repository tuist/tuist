# Tuist ClusterClass + Cluster CRs

Self-hosted Kubernetes manifests for the four Tuist workload clusters
(staging / canary / production / preview), reconciled by our own
management cluster running CAPI + caph.

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
| `tuist-staging` | 3× cpx22 | md-0: 2× cpx31 |
| `tuist-canary` | 3× cpx22 | md-0: 2× cpx31 |
| `tuist` (production) | 3× cpx22 | md-0: 2× ccx23 (`pool=general`); md-processor: 2× cpx62 (`pool=processor`, autoscaled 2→6) |
| `tuist-preview` | 1× cpx22 | md-0: 1× cpx42 |

Variables exposed by the ClusterClass: control plane replicas + machine
type, per-pool machine type, region (default `fsn1`), SSH key name,
optional Hetzner Cloud Network config, optional placement groups.

## Image strategy

Hetzner-published Ubuntu images plus cloud-init that installs containerd
+ runc + kubelet at first boot (~2–3 min cold start). Simple to reason
about; no Packer pipeline. Acceptable for the autoscaler's `md-processor`
2→6 cadence; if scaling latency becomes painful we can introduce a
pre-baked image without changing the ClusterClass shape.

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
- `containerRuntimeEndpoint`, `staticPodPath`, `cgroupDriver`, `clusterDNS`, `clusterDomain` added to the kubelet `KubeletConfiguration` shipped via the `files:` block. Critical: kubelet is invoked with two `--config` flags (kubeadm's default + ours via `kubeletExtraArgs`) and the second OVERRIDES the first, so any field omitted here gets cleared.
- `resolvConf` deliberately NOT set on the kubelet `KubeletConfiguration`, and the caph reference's `/etc/kubernetes/resolv.conf` (Cloudflare-only) is dropped. Kubelet falls back to the host's `/etc/resolv.conf`, which DHCP populates with Hetzner's resolvers (multi-IP, dual-stack, one network hop away). Same DNS posture Apalla shipped on the workload clusters; avoids regressing to single-provider DNS.
