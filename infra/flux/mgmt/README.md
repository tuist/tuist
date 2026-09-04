# Flux on the management cluster

Flux reconciles the workload `Cluster` resources from git onto the
self-hosted CAPI + caph **management cluster** (single-node Talos). This is
**Pillar 1** of [hive/specs/72](https://hive.tuist.dev/specs/72): continuous
GitOps reconciliation, so drift is corrected on an interval instead of only
on merge, and no routine change needs the break-glass kubeconfig.

Health alerting is a separate, independent path — **Pillar 2**, Grafana
Cloud (`infra/helm/k8s-monitoring/values-management.yaml` +
`infra/helm/k8s-monitoring/alerts.md`). A GitOps dashboard is not the health
mechanism; a degraded control plane pages via Grafana Cloud.

## What Flux owns (and deliberately does not)

| Owned by Flux (`infra/k8s/clusters/workloads/`) | Kept on `mgmt-cluster-apply.yml` |
|---|---|
| `tuist-staging`, `tuist-canary`, `tuist` (production) | `clusterclass-tuist.yaml`, `bare-metal*.yaml` (immutable templates — the delete-and-apply fallback for `field is immutable` can't be reproduced by a Kustomization) |
| tenants `hive-production`, `once-production`, `atlas-production` | `cluster-preview.yaml` (replicas mutated out-of-band by the preview workflows; Flux would fight them every interval) and `cluster-pentest.yaml` (isolated security-assessment cluster) |
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

### Before you begin

Every command in this section targets the **management** cluster, which is not
in the usual kubeconfig — those contexts are all workload clusters, and a
`view` identity there cannot even list Secrets. Load the break-glass
kubeconfig and confirm you are on mgmt before anything else; only the mgmt
cluster serves the CAPI CRDs:

```bash
op document get "kubeconfig: tuist-mgmt" --vault tuist-k8s-mgmt \
  --output ./mgmt.kubeconfig && chmod 600 ./mgmt.kubeconfig
export KUBECONFIG=./mgmt.kubeconfig
kubectl get clusters.cluster.x-k8s.io -A   # errors on a workload cluster
```

Keep `./mgmt.kubeconfig` out of git — it is a cluster-admin credential for
every workload cluster, sitting in a public repo's worktree.

### Bootstrap — run this AFTER the PR adding this directory has merged

Flux reconciles `--branch=main`. The per-cluster `Kustomization` CRs here, and
the `workloads/` Cluster CRs they point at, only exist on `main` once that PR
lands — so bootstrapping earlier installs a Flux that reconciles nothing.
Bootstrapping before the merge is harmless but pointless; bootstrapping after
is what activates reconciliation.

`flux-system/` (`gotk-components.yaml`, `gotk-sync.yaml`, `kustomization.yaml`)
is **already committed here**, generated with `flux install --export` at the
pinned version below using bootstrap's default component set
(source / kustomize / helm / notification controllers). `flux bootstrap` is
idempotent: it adopts those files rather than rewriting them, provided you run
the same version. Keep it in step with the `fluxcd/flux2/action` pin in
`.github/workflows/flux-diff.yml` so CI and the cluster agree.

Pre-flight first — it is non-mutating and confirms the cluster can host Flux:

```bash
flux check --pre
```

Then bootstrap. The App credentials live in the `FLUX_GITHUB_APP` item in
`tuist-k8s-mgmt` (fields `app_id` / `installation_id`, plus the
`private-key.pem` attachment):

```bash
export FLUX_GITHUB_APP_ID=$(op read --account tuist.1password.com \
  "op://tuist-k8s-mgmt/FLUX_GITHUB_APP/app_id")
export FLUX_GITHUB_APP_INSTALLATION_ID=$(op read --account tuist.1password.com \
  "op://tuist-k8s-mgmt/FLUX_GITHUB_APP/installation_id")
op read --account tuist.1password.com \
  "op://tuist-k8s-mgmt/FLUX_GITHUB_APP/private-key.pem" \
  --out-file ./flux-app.pem && chmod 600 ./flux-app.pem

flux bootstrap github \
  --owner=tuist \
  --repository=tuist \
  --branch=main \
  --path=infra/flux/mgmt \
  --app-id="$FLUX_GITHUB_APP_ID" \
  --app-installation-id="$FLUX_GITHUB_APP_INSTALLATION_ID" \
  --app-private-key-file=./flux-app.pem

rm -f ./flux-app.pem
```

The root Kustomization in `gotk-sync.yaml` (path `./infra/flux/mgmt`) then
reconciles the per-cluster `Kustomization` CRs in this directory, and Flux
tracks and upgrades itself from git thereafter.

Then wire credential rotation, so the App key is ESO-synced rather than frozen
at whatever bootstrap wrote:

```bash
kubectl apply -f ../../k8s/mgmt/flux-git-externalsecret.yaml
```

Verify — expect `flux-system` Ready plus one Kustomization per cluster:

```bash
flux check && flux get kustomizations -A
```

### Harden the source (optional, after bootstrap)

Path-scoping already prevents Flux from touching the immutable templates,
preview or pentest — no Kustomization `path` reaches them. A `spec.ignore` on
the `flux-system` `GitRepository` is a second guard, and in a monorepo this
size it also keeps the source artifact small (source-controller otherwise
packages the whole repository on every sync).

Two cautions before adding one:

- `spec.ignore` **replaces** Flux's built-in default excludes rather than
  adding to them, so anything you rely on being excluded must be restated.
- The tempting "exclude everything, re-include two paths" form does not work
  naively: `.sourceignore` uses gitignore semantics, and a path cannot be
  re-included once a parent directory is excluded. Each level has to be
  re-opened (`/*`, `!/infra`, `/infra/*`, `!/infra/k8s`, …).

The straightforward version, enumerating what must never be reconciled:

```yaml
# infra/flux/mgmt/flux-system/gotk-sync.yaml — GitRepository spec:
spec:
  ignore: |
    /infra/k8s/clusters/clusterclass-tuist.yaml
    /infra/k8s/clusters/bare-metal*.yaml
    /infra/k8s/clusters/machinedrainrules.yaml
    /infra/k8s/clusters/cluster-preview.yaml
    /infra/k8s/clusters/cluster-pentest.yaml
```

Commit it, then confirm the source still reconciles before trusting it:

```bash
flux get sources git flux-system
```

## Pre-enable gate: confirm the first reconcile is a no-op

Before letting Flux reconcile, diff every workload `Cluster` against live. An
empty diff means the first sync changes nothing; anything else is a live
mutation you are about to make unattended.

```bash
for c in staging canary production hive once atlas; do
  echo "== $c =="
  kubectl kustomize "infra/k8s/clusters/workloads/$c" | kubectl diff -f - || true
done
```

This is not theoretical: the first run of this gate found that the imported
tenant CRs (hive / once / atlas) were **not** no-ops. They had been checked
against the `tuist/{hive,once,atlas}` repos, but those drifted from live
because nothing ever applied them to the mgmt cluster. Two classes of problem
showed up, both since fixed by syncing the manifests to live:

- **Defaulted ClusterClass variables.** CAPI materializes all of them onto the
  live object, so a CR declaring only a subset makes Flux delete and re-order
  the list on every reconcile. Declare the full set.
- **Genuine topology drift** — atlas carried an `md-0` pool label live did not
  have.

`production` keeps one intentional diff: `md-processor` has no `replicas` in
git, so the first reconcile removes that field from the Cluster CR and hands
the pool's replica count to cluster-autoscaler. It does not change the running
node count — it changes which controller owns it.

## Health of Flux itself

A down reconciler stops correcting drift, so Flux's controllers are scraped
and heartbeat-alerted via Pillar 2 (`infra/helm/k8s-monitoring/values-management.yaml`
+ `infra/helm/k8s-monitoring/alerts.md`). Grafana Cloud evaluates the alerts
outside this single-node cluster.

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
