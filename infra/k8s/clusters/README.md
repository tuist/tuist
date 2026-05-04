# Tuist ClusterClass + Cluster CRs

Self-hosted Kubernetes cluster manifests for the four workload clusters
(staging / canary / production / preview), targeting our own management
cluster running CAPI + caph (no Syself, no Apalla, no CSO).

## Why a ClusterClass

Originally the workload clusters were CAPI `Cluster` CRs that referenced
Syself's proprietary `hetzner-apalla-1-34-v6` ClusterStack. When we moved
off Syself we discovered the Apalla stack isn't publicly available, so we
needed to replace it with something we own.

ClusterClass is CAPI's native templating layer. We author one
`ClusterClass` that defines the reusable shape (HA control plane,
worker-pool variables, network config, KubeadmControlPlaneTemplate,
HCloudMachineTemplate), and per-cluster `Cluster` CRs reference it via
`topology.classRef.name`, only specifying what differs (replica counts,
machine types per pool, labels/taints).

## Layout

```
clusters/
├── README.md                  this file
├── clusterclass-tuist.yaml    our ClusterClass
├── cluster-staging.yaml       per-env Cluster CRs in topology mode
├── cluster-canary.yaml
├── cluster-production.yaml
└── cluster-preview.yaml
```

`clusterclass-tuist.yaml` was originally forked from caph's `cluster-class.yaml` release asset, with adaptations captured in [Status](#status) below. When caph ships a new minor and we want to compare against upstream, pull the relevant release tarball at that time:

```bash
gh release download v1.2.0 --repo syself/cluster-api-provider-hetzner \
  --pattern 'cluster-class*.yaml' --pattern 'cluster-template-hcloud*.yaml'
```

## Target shape per cluster

Mirroring what's currently on Syself (see `infra/k8s/syself/workload-cluster-*.yaml`):

| Cluster | CP | Workers |
|---|---|---|
| `tuist-staging` | 3× cpx22 | md-0: 2× cpx31 |
| `tuist-canary` | 3× cpx22 | md-0: 2× cpx31 |
| `tuist` (production) | 3× cpx22 | md-0: 2× ccx23 (`pool=general`); md-processor: 2× cpx62 (`pool=processor`) |
| `tuist-preview` | 1× cpx22 | md-0: 1× cpx42 |

Variables exposed by the ClusterClass: control plane replicas + machine type, per-pool machine type, region (default `fsn1`), SSH key name, optional Hetzner Cloud Network config.

## Image strategy

caph's reference templates use Hetzner-published Ubuntu images plus cloud-init that installs kubeadm + container runtime + kubelet at first boot. ~2–3 min cold-start vs Apalla's ~30s with pre-baked images. For our scale (autoscaler scaling `md-processor` 2→6), the simplicity of vanilla Ubuntu outweighs the boot-time delta. We can introduce a Packer-built pre-baked image later if scaling latency becomes painful.

## Status

- [x] `clusterclass-tuist.yaml` forked from caph v1.1.0's `cluster-class.yaml` release asset. Adaptations from the validation runs:
  - Bare-metal MachineDeployment class + bare-metal templates dropped (we only use cloud servers).
  - All 5 resources scoped to the `org-tuist` namespace (otherwise `topology.classRef` lookup fails because Cluster CRs live in `org-tuist`).
  - `initConfiguration.skipPhases: [addon/kube-proxy]` added to the KCP because Cilium replaces kube-proxy on Tuist's clusters.
  - `hcloudPlacementGroups` variable defaults to `[]` (otherwise the patch errors at render time).
  - `hcloudControlPlanePlacementGroupName` and `hcloudWorkerMachinePlacementGroupName` patches split into separate `enabledIf` definitions: caph errors with "Placement group does not exist" if the field is set to empty string.
  - `KUBERNETES_VERSION=1.34.6` and `CONTAINERD=2.2.3` in `preKubeadmCommands` ported from the flat `cluster-template-hcloud.yaml`. The reference ClusterClass hardcodes `KUBERNETES_VERSION=1.35.4` and uses an old `cri-containerd-cni-` bundle that's no longer published for containerd 2.x.
  - Added `containerd.service` systemd unit to both KCP and worker `files:` blocks. The plain `containerd-` tarball doesn't ship one (only the older `cri-containerd-cni-` bundle did). Without this, `systemctl start containerd` finds no unit and PLEG never goes healthy.
  - Added `containerRuntimeEndpoint`, `staticPodPath`, `cgroupDriver`, `clusterDNS`, `clusterDomain` to the kubelet `KubeletConfiguration` shipped via the `files:` block. Critical: kubelet is invoked with two `--config` flags (kubeadm's default + ours via `kubeletExtraArgs`); the second OVERRIDES the first, so any field not set in our config gets cleared. Without `containerRuntimeEndpoint` kubelet can't talk to containerd → PLEG never healthy → static pods never start.
- [x] Per-env Cluster CRs (`cluster-{staging,canary,production,preview}.yaml`) authored in topology mode against `tuist-hcloud`.
- [x] **Validation against a throwaway 5th cluster: passing.** Full end-to-end: caph provisions Hetzner LB + server, cloud-init runs, containerd 2.2.3 starts, kubeadm init succeeds, all 4 control-plane static pods come up (etcd / kube-apiserver / kube-controller-manager / kube-scheduler), workload-cluster API responds via the LB, kubeconfig Secret is minted. ~2.3 min from `kubectl apply` to `ControlPlaneInitialized=True`. Cost per validation run: ~€0.30.

## Cutover

The ClusterClass + per-env CRs are checked in and validated. The remaining work depends on the Cluster CRs being on our mgmt cluster (i.e. after the Syself cutover completes):

1. Diff the rendered KubeadmControlPlane / KubeadmConfigTemplate / HCloudMachineTemplate that `tuist-hcloud` would produce vs. the Apalla originals already on the mgmt cluster. Iterate the ClusterClass until the diff is either empty (no-op classRef swap) or limited to fields CAPI is happy to reconcile in place (labels, annotations).
2. Per-cluster swap once the diff is acceptable:
   ```bash
   kubectl -n org-tuist patch cluster <name> --type=merge \
     -p '{"spec":{"topology":{"classRef":{"name":"tuist-hcloud"}}}}'
   ```
   Stagger across staging → canary → production → preview. Watch `kubectl -n org-tuist get machine -w` for unexpected deletions.

After the last swap, K8s minor bumps become `topology.version:` edits and we own the full cluster spec.
