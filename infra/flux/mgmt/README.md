# Flux on the management cluster

Flux reconciles management-cluster desired state from git onto the
self-hosted CAPI + caph **management cluster** (single-node Talos). This is
**Pillar 1** of [hive/specs/72](https://hive.tuist.dev/specs/72): continuous
GitOps reconciliation, so drift is corrected on an interval instead of only
on merge, and no routine change needs the break-glass kubeconfig.

Health alerting is a separate, independent path — **Pillar 2**, Grafana
Cloud (`infra/helm/k8s-monitoring/values-management.yaml` +
`infra/helm/k8s-monitoring/alerts.md`). A GitOps dashboard is not the health
mechanism; a degraded control plane pages via Grafana Cloud.

## What Flux owns (and deliberately does not)

| Owned by Flux | Kept on `mgmt-cluster-apply.yml` |
|---|---|
| `tuist-staging`, `tuist-canary`, `tuist` (production) | `clusterclass-tuist.yaml`, `bare-metal*.yaml` (immutable templates — the delete-and-apply fallback for `field is immutable` can't be reproduced by a Kustomization) |
| tenants `hive-production`, `once-production`, `atlas-production` | `cluster-preview.yaml` (replicas mutated out-of-band by the preview workflows; Flux would fight them every interval) and `cluster-pentest.yaml` (isolated security-assessment cluster) |
| Cloudflare operator Helm release and `tuist.dev` rate-limit configuration | the other mgmt-side workloads (etcd-snapshot, tailscale, autoscaler, hetzner-robot-controller) |

One Flux `Kustomization` per cluster (`cluster-*.yaml` here), each `path`
scoped to a single `workloads/<cluster>/` subdir. Key invariants:

- **`prune: false`** — a git deletion never tears down a live `Cluster`.
- **`force: false`** — on a server-side-apply conflict with CAPI's topology
  controller, Flux halts and reports instead of stomping it.
- **`healthCheckExprs`** gate each Kustomization on the `Cluster`'s v1beta2
  `Available` rollup (a sync gate, not health alerting).

`cloudflare-operator.yaml` follows the same child-Kustomization pattern,
but points at a local Helm release and waits for it to become ready. Its
managed values pin the operator image by digest. `cloudflare-config.yaml`
depends on that release and applies the Cloudflare resources under
`infra/flux/cloudflare-config/`, preventing Flux from applying a custom
resource before its definition exists.

The adopted rate-limit resource starts in `read_only`. That mode deliberately
reports `Ready=False`, so the configuration Kustomization does not wait on
resource health. Before changing it to `active`, inspect the proposed change:

```bash
kubectl get cloudflareratelimit public-pages-anti-bombardment \
  -o jsonpath='{.status.message}{"\n"}{.status.proposedChanges}{"\n"}'
```

Only an empty `status.proposedChanges` and an `in sync (adopted)` message are
safe to activate. The `cloudflare-operator/token` field in the
`tuist-k8s-mgmt` 1Password vault should be read-only for this adoption pass;
replace it with a zone-scoped token carrying `Zone WAF:Edit`, where WAF means
[Web Application Firewall](https://www.cloudflare.com/learning/ddos/glossary/web-application-firewall-waf/),
only when the resource is switched to `active`.

## Install (one-time, break-glass)

Land [External Secrets Operator on the mgmt cluster](../../k8s/mgmt/) first —
it supplies Flux's git credential. Installing Flux is the one unavoidable
break-glass step; afterwards Flux self-manages, upgrades included.

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

### Install — what was actually done, and why not `flux bootstrap`

Flux was installed by applying the manifests committed here, **not** with
`flux bootstrap`. That is the supported path for this repository and the one to
repeat on a rebuild. `flux bootstrap` should not be run against this cluster:

- It authenticates with a PAT or SSH deploy key and **pushes a commit to
  `main`**, which is protected and expects review.
- It **regenerates `gotk-sync.yaml` from CLI flags**, and 2.9.5 has no flag for
  the GitRepository provider — so it strips `spec.provider: github`,
  source-controller falls back to basic auth, ignores the ESO-synced App fields,
  and reconciliation dies quietly. `kustomization.yaml` re-asserts the provider
  as a patch to survive exactly this, but not running bootstrap avoids it.
- Everything it would set up already exists: `flux-system/` is committed here
  (reviewed, rather than pushed unreviewed), and the git credential comes from
  ESO rather than a bootstrap-written deploy key.

Install in stages so the controllers are healthy before anything reconciles:

```bash
# 1. Controllers only — creates no GitRepository/Kustomization, reconciles nothing.
kubectl apply -f flux-system/gotk-components.yaml
kubectl -n flux-system rollout status deploy/source-controller --timeout=180s
kubectl -n flux-system rollout status deploy/kustomize-controller --timeout=180s

# 2. Git credential, before anything tries to authenticate.
kubectl apply -f ../../k8s/mgmt/flux-git-externalsecret.yaml
kubectl -n flux-system wait externalsecret/flux-system-git-auth \
  --for=condition=Ready --timeout=120s

# 3. Activate: GitRepository + root Kustomization, built so the provider patch applies.
kubectl kustomize flux-system \
  | yq eval-all 'select(.kind == "GitRepository" or (.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/v1"))' - \
  | kubectl apply -f -
```

Verify — expect nine Kustomizations Ready and the provider set:

```bash
kubectl -n flux-system get kustomizations
kubectl -n flux-system get gitrepository flux-system \
  -o jsonpath='{.spec.provider}{"\n"}'   # must print: github
```

Flux self-manages from here: the root Kustomization's `path` is this directory,
so its inventory includes `flux-system/` itself (controllers, CRDs, RBAC). An
upgrade is `flux install --export` at the new version over
`flux-system/gotk-components.yaml`, merged like any other change — Flux then
applies it to itself. Keep the version in step with the `fluxcd/flux2/action`
pin in `.github/workflows/flux-diff.yml`.

### Suspending and resuming a Kustomization

`suspend` is the tool for stopping Flux from re-applying something while you fix
git. Resuming has an ordering trap that has already caused one production
scale-down:

```bash
kubectl -n flux-system patch kustomization cluster-<name> --type=merge \
  -p '{"spec":{"suspend":true}}'
```

**Before resuming, force the source to fetch and confirm the revision.** The
GitRepository polls on its own interval, so immediately after a fix merges the
cached artifact is still the *old* commit — resuming then reconciles the very
content you suspended to escape:

```bash
kubectl -n flux-system annotate gitrepository flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
kubectl -n flux-system get gitrepository flux-system \
  -o jsonpath='{.status.artifact.revision}{"\n"}'   # must be the commit with the fix

kubectl -n flux-system patch kustomization cluster-<name> --type=merge \
  -p '{"spec":{"suspend":false}}'
```

### Harden the source (optional)

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

Add it as a patch in `kustomization.yaml`, next to the provider one — **not**
directly in `gotk-sync.yaml`, which `flux bootstrap` rewrites:

```yaml
# infra/flux/mgmt/flux-system/kustomization.yaml — add alongside the provider patch:
patches:
  - target:
      kind: GitRepository
      name: flux-system
    patch: |
      - op: add
        path: /spec/ignore
        value: |
          /infra/k8s/clusters/clusterclass-tuist.yaml
          /infra/k8s/clusters/bare-metal*.yaml
          /infra/k8s/clusters/machinedrainrules.yaml
          /infra/k8s/clusters/cluster-preview.yaml
          /infra/k8s/clusters/cluster-pentest.yaml
```

Commit it, then confirm the source still reconciles before trusting it:

```bash
kubectl -n flux-system get gitrepository flux-system \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status} {.status.artifact.revision}{"\n"}'
```

## Pre-enable gate: confirm a reconcile would be a no-op

Before letting Flux reconcile a cluster for the first time — or after
resuming a suspended one — diff it against live. An
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

A down reconciler stops correcting drift without breaking anything visible, so
Flux is watched from Grafana Cloud, which evaluates outside this single-node
cluster. Two rules are live (`infra/helm/k8s-monitoring/alerts.md`):

- **`Flux - reconciliation has stalled fleet-wide`** on
  `gotk_reconcile_duration_seconds_count`. A fleet total, so suspending one
  Kustomization does not page.
- **`Flux - telemetry missing from the management cluster`**, the paired
  `absent_over_time` rule. The stall rule compares a counter, so if the
  controllers vanish the series goes too and that comparison returns No Data,
  which is Normal here; this rule is what catches Flux not running at all.

Both read metrics collected by pod-annotation autodiscovery, not an explicit
scrape config.

Neither detects a reconcile that runs and **fails**: the duration histogram
counts failed reconciles too, and Flux 2.9.5 does not export
`gotk_reconcile_condition`. That gap is closed by a kube-state-metrics
custom-resource-state config for Kustomizations in `values-management.yaml`,
using the same mechanism as the CAPI custom-resource metrics. The rule that
consumes it is written up in `alerts.md` and is deliberately **not created until
the series is confirmed flowing**, because a rule whose query matches nothing
reads as passing.

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
