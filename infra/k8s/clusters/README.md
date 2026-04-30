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
├── README.md                      this file
├── reference-templates/           caph v1.1.0 release assets, unchanged
│   ├── cluster-class.yaml         caph's reference ClusterClass (fork starting point)
│   ├── cluster-class-topology-example.yaml   per-cluster Cluster CR shape
│   ├── cluster-template-hcloud.yaml          single-cluster non-topology template
│   └── cluster-template-hcloud-network.yaml  same with Hetzner Cloud Network
└── (TODO) clusterclass-tuist.yaml           our forked + adapted ClusterClass
└── (TODO) cluster-{staging,canary,production,preview}.yaml   per-env Cluster CRs
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
- [ ] Fork into `clusterclass-tuist.yaml` and adapt for our two-pool production case
- [ ] Validate against a throwaway 5th cluster on the new mgmt cluster
- [ ] Convert each of the 4 `infra/k8s/syself/workload-cluster-*.yaml` files to topology mode pointing at `tuist-hcloud`
- [ ] `clusterctl move` migration via the existing runbook (Phase 3)
