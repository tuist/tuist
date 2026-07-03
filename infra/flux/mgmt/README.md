# Flux on the management cluster

Flux reconciles the workload `Cluster` resources from git onto the
self-hosted CAPI + caph **management cluster** (single-node Talos). This is
**Pillar 1** of [hive/specs/72](https://hive.tuist.dev/specs/72): continuous
GitOps reconciliation, so drift is corrected on an interval instead of only
on merge, and no routine change needs the break-glass kubeconfig.

Health alerting is a separate, independent path — **Pillar 2**, Grafana
Cloud (`infra/helm/k8s-monitoring/values-mgmt.yaml`). A GitOps dashboard is
not the health mechanism; a degraded control plane pages via Grafana Cloud.

## What Flux owns (and deliberately does not)

| Owned by Flux (`infra/k8s/clusters/workloads/`) | Kept on `mgmt-cluster-apply.yml` |
|---|---|
| `tuist-staging`, `tuist-canary`, `tuist` (production) | `clusterclass-tuist.yaml`, `bare-metal*.yaml` (immutable templates — the delete-and-apply fallback for `field is immutable` can't be reproduced by a Kustomization) |
| tenants `hive-production`, `once-production`, `atlas-production` | `cluster-preview.yaml` (its replicas are mutated out-of-band by the preview workflows; Flux would fight them every interval) |
| | the mgmt-side workloads (etcd-snapshot, tailscale, autoscaler, hetzner-robot-controller) |

One Flux `Kustomization` per cluster (`cluster-*.yaml` here), each `path`
scoped to a single `workloads/<cluster>/` subdir. Key invariants:

- **`prune: false`** — a git deletion never tears down a live `Cluster`.
- **`force: false`** — on a server-side-apply conflict with CAPI's topology
  controller, Flux halts and reports instead of stomping it.
- **`healthCheckExprs`** gate each Kustomization on the `Cluster`'s v1beta2
  `Available` rollup (a sync gate, not health alerting).

## Bootstrap (one-time, break-glass)

Land [External Secrets Operator on the mgmt cluster](../../k8s/mgmt/) first
(it syncs Flux's git credential), then bootstrap declaratively. This is the
one unavoidable break-glass step — afterwards Flux self-manages, upgrades
included.

```bash
# Uses the emergency mgmt kubeconfig (1Password: "kubeconfig: tuist-mgmt",
# vault tuist-k8s-mgmt) and a dedicated single-repo GitHub App whose
# private key + app/installation IDs are ESO-synced from tuist-k8s-mgmt.
flux bootstrap github \
  --owner=tuist \
  --repository=tuist \
  --branch=main \
  --path=infra/flux/mgmt \
  --app-id="$FLUX_GITHUB_APP_ID" \
  --app-installation-id="$FLUX_GITHUB_APP_INSTALLATION_ID" \
  --app-private-key-file=./flux-app.pem
```

Bootstrap writes `infra/flux/mgmt/flux-system/` (`gotk-components.yaml`,
`gotk-sync.yaml`, `kustomization.yaml`) and commits it, so Flux tracks and
upgrades itself from git thereafter. The root Kustomization in
`gotk-sync.yaml` (path `./infra/flux/mgmt`) then reconciles the per-cluster
`Kustomization` CRs in this directory.

### Harden the source (belt-and-suspenders)

Path-scoping already prevents Flux from touching the immutable templates or
preview (no Kustomization `path` reaches them). As a second guard, add a
`spec.ignore` to the bootstrap-created `flux-system` `GitRepository` so those
files never even enter the Flux source artifact, then commit it:

```yaml
# infra/flux/mgmt/flux-system/gotk-sync.yaml — GitRepository spec:
spec:
  ignore: |
    # exclude everything the mgmt Flux must never reconcile
    /infra/k8s/clusters/clusterclass-tuist.yaml
    /infra/k8s/clusters/bare-metal*.yaml
    /infra/k8s/clusters/cluster-preview.yaml
```

## Health of Flux itself

A down reconciler stops correcting drift, so Flux's controllers are scraped
and heartbeat-alerted via Pillar 2 (`infra/helm/k8s-monitoring/values-mgmt.yaml`
+ `alerts/`). Grafana Cloud evaluates the alerts outside this single-node
cluster.

## Removing a cluster (explicit destroy flow)

Because Flux never prunes a `Cluster`, deleting the manifest from git leaves
the infrastructure running (the stale-cluster check in
`infra/k8s/mgmt/reconciliation-checks.yaml` reports it). Intentional removal:

1. Remove `infra/k8s/clusters/workloads/<cluster>/` and its
   `infra/flux/mgmt/cluster-<cluster>.yaml` Kustomization in a PR.
2. After merge, under break-glass: `kubectl delete cluster <name> -n org-tuist`.

## Break-glass: recovering a wedged Flux

The emergency mgmt kubeconfig stays in `tuist-k8s-mgmt` for exactly three
things (see spec/72 Decision 6): the one-time bootstrap above; recovering
Flux when it cannot reconcile itself (bad upgrade, source-controller can't
reach git, RBAC lockout) by applying the corrective manifest directly until
git access is restored; and manifests still outside Flux's scope (the
ClusterClass/templates, preview, mgmt-side workloads). Routine cluster and
Flux changes go through git.
