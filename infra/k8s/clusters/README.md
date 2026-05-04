# Tuist ClusterClass + Cluster CRs

> **⚠️ DO NOT `kubectl apply` `cluster-*.yaml` OR `clusterclass-tuist.yaml` UNTIL PHASE 7 COMPLETES.**
>
> The ClusterClass renders against caph's reference templates which are stale relative to the flat `cluster-template-hcloud.yaml`: `containerd 2.x` needs a `containerd.service` systemd unit shipped in the flat template's `files:` block but missing from this ClusterClass. Applying the per-env Cluster CRs today will provision Hetzner servers that fail mid-bootstrap (kubeadm `init` can't reach containerd's socket). The migration path in [`infra/k8s/self-hosted-migration.md`](../self-hosted-migration.md) (Phases 2/3) does NOT depend on this; `clusterctl move` brings the existing Apalla-rendered KCP/MD/templates over and they keep reconciling. See [Status](#status) and [Next steps to make this swappable](#next-steps-to-make-this-swappable) below.

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
├── README.md                          this file
├── clusterclass-tuist.yaml            our ClusterClass (in progress, see "Status")
├── cluster-staging.yaml               per-env Cluster CRs in topology mode
├── cluster-canary.yaml
├── cluster-production.yaml
├── cluster-preview.yaml
└── reference-templates/               caph v1.1.0 release assets, unchanged
    ├── cluster-class.yaml             caph's reference ClusterClass (fork source)
    ├── cluster-class-topology-example.yaml   per-cluster Cluster CR shape
    ├── cluster-template-hcloud.yaml          single-cluster non-topology template
    └── cluster-template-hcloud-network.yaml  same with Hetzner Cloud Network
```

The `reference-templates/` directory is checked in for traceability:
when caph publishes a new minor (v1.2.0+), the diff against this
snapshot tells us what upstream changed in the ClusterClass shape.

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

- [x] caph reference templates pulled to `reference-templates/`
- [x] `clusterclass-tuist.yaml` forked from `cluster-class.yaml` with these adaptations:
  - Bare-metal MachineDeployment class + bare-metal templates dropped (we only use cloud servers).
  - All 5 resources scoped to the `org-tuist` namespace (otherwise `topology.classRef` lookup fails because Cluster CRs live in `org-tuist`).
  - `initConfiguration.skipPhases: [addon/kube-proxy]` added to the KCP because Cilium replaces kube-proxy on Tuist's clusters.
  - `hcloudPlacementGroups` variable defaults to `[]` (otherwise the patch errors at render time).
  - `hcloudControlPlanePlacementGroupName` and `hcloudWorkerMachinePlacementGroupName` patches split into separate `enabledIf` definitions: caph errors with "Placement group does not exist" if the field is set to empty string.
  - `KUBERNETES_VERSION` and `CONTAINERD` versions in `preKubeadmCommands` ported from the flat `cluster-template-hcloud.yaml`. The reference ClusterClass hardcodes `KUBERNETES_VERSION=1.35.4` and uses an old `cri-containerd-cni-` bundle that's no longer published for containerd 2.x.
- [x] Per-env Cluster CRs (`cluster-{staging,canary,production,preview}.yaml`) authored in topology mode against `tuist-hcloud`.
- [ ] **Validation against a throwaway 5th cluster: blocked.** End-to-end provisioning fails at the kubeadm-init phase because containerd 2.2.3 needs a systemd service file that the flat template ships in its `files:` block but caph's reference ClusterClass doesn't include. The fix is to port the `containerd.service` file definition (and any other gaps) from `cluster-template-hcloud.yaml`'s `files:` block into our ClusterClass's KCP and worker `files:` blocks. Hasn't been done yet.
- [ ] `clusterctl move` migration via the existing runbook (Phase 3) does **not** depend on this. `clusterctl move` brings the existing Apalla-rendered KubeadmControlPlane / KubeadmConfigTemplate / HCloudMachineTemplate over as plain CAPI resources; caph reconciles them without needing `tuist-hcloud` to render anything new. The Cluster CRs keep `topology.classRef.name: hetzner-apalla-1-34-v6` (which doesn't resolve on our mgmt cluster, so the topology controller errors gracefully without taking destructive action). The `tuist-hcloud` swap happens later, when this ClusterClass produces working clusters end-to-end.

## Next steps to make this swappable

1. Port the `files:` block from `reference-templates/cluster-template-hcloud.yaml` (specifically the `containerd.service` systemd unit at lines 68-114 of the upstream file) into both the KCP `files:` and the worker `files:` in `clusterclass-tuist.yaml`.
2. Validate end-to-end against a throwaway 5th cluster (the existing test fixture in this directory is sufficient, just `kubectl apply` it).
3. Once a fresh cluster comes Ready and a smoke pod schedules, diff the rendered KubeadmControlPlane / KubeadmConfigTemplate / HCloudMachineTemplate against the moved Apalla originals on the mgmt cluster (after Phase 3 cutover). Iterate the ClusterClass until the diff is empty (no-op swap) or limited to fields CAPI is happy to reconcile in place.
4. Per-cluster swap: `kubectl patch cluster <name> --type=merge -p '{"spec":{"topology":{"classRef":{"name":"tuist-hcloud"}}}}'`. Stagger across staging → canary → production → preview, watching for unexpected Machine deletions.
