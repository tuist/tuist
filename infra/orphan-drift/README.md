# Orphan drift check

Finds live Kubernetes objects that **no chart on `main` renders** and that
**no controller owns**.

- Check: [`infra/mise/tasks/k8s/orphan-drift-check.sh`](../mise/tasks/k8s/orphan-drift-check.sh)
- Schedule: [`.github/workflows/orphan-drift.yml`](../../.github/workflows/orphan-drift.yml), Mondays 07:00 UTC, one Slack message per run
- Config: [`releases.txt`](releases.txt) (chart → environment wiring), [`allowlist.txt`](allowlist.txt)

## Why

Three orphans were found by hand on 2026-08-18/19:

| Orphan | Cluster | Age | Why nothing caught it |
| --- | --- | --- | --- |
| `registry/registry-pg` CNPG cluster ([#12442](https://github.com/tuist/tuist/issues/12442)) | production | 43d `Pending` | Created by a `registry` chart that only ever existed on a feature branch. No `helm upgrade` from `main` could prune it, and `helm list` showed a healthy release the whole time. |
| 11 `kura-<account>-staging` KuraInstances ([#12467](https://github.com/tuist/tuist/issues/12467)) | staging | 33d unschedulable | Stranded in the retired `hetzner-staging-runners` region. Their Postgres rows were gone, and the reconciler that removes them is row-driven, so it could not see them. |
| `kuragateways.kura.tuist.dev` CRD + CR + Deployment | all three | 6 weeks | Helm does not prune CRDs, so the CRD outlived the controller removed in [#11644](https://github.com/tuist/tuist/pull/11644). |

None appeared in a dashboard, an alert, or Helm state. Each was found because
a person went looking.

## How it decides

An object is reported when all three hold:

1. Its identity `(group, Kind, namespace, name)` is absent from the union of
   every chart in `releases.txt` rendered for that environment.
2. It has no `ownerReferences`.
3. It is older than `MIN_AGE_HOURS` (default 24) and not already terminating.

The owner-reference filter is what makes the report readable. The clusters are
full of objects no chart renders on purpose — CNPG's Pods and Services, the
kura-controller's StatefulSets, every ReplicaSet — and every one of them
carries an `ownerReference` to whatever reconciles it. An object with no owner
is one nothing is watching. Measured on the first run: 747 unowned objects
across the three clusters, 8 findings after the allowlist.

Policed kinds are `Namespace`, `Service`, `Deployment`, `StatefulSet`,
`CustomResourceDefinition`, and every resource in the API groups we own
(`kura.tuist.dev`, `tuist.dev`, `postgresql.cnpg.io`). Those are the kinds
that cost money or serve traffic when abandoned; a stranded ConfigMap is
inert.

**Helm state is deliberately not consulted.** "Belongs to a live Helm release"
is the tempting exemption and it is the wrong one: `registry-pg` had a
perfectly healthy release, created by a chart that never reached `main`. Helm
state is precisely the signal that failed.

## Acting on a finding

The check never deletes, and it should not start to. Two of the three known
cases needed a human decision about whether the data behind them mattered.

1. **Establish what created it.** `kubectl get <kind> <name> -o yaml`. A
   `kubectl.kubernetes.io/last-applied-configuration` annotation means it was
   hand-applied. `app.kubernetes.io/managed-by: Helm` without a release that
   renders it means a branch-only chart or a wrong-namespace apply.
2. **Establish whether it does anything.** Zero endpoints, zero ready
   replicas, `Pending` for weeks — or, worse, warm capacity nobody asked for.
3. **Decide.** Either delete it, or add an allowlist rule with a reason. Both
   are fine outcomes; leaving it in the report is not, because a report with
   permanent noise stops being read.

## Tuning the allowlist

Rules are `<group>/<Kind>  <namespace>  <name>`, `core` for the core group,
`-` for cluster-scoped, `*` the only wildcard, and a reason after `#`.

Keep rules narrow. All three known orphans were a single object inside a
namespace full of legitimate ones, so a rule that covers a whole namespace or
a whole API group is usually a rule that will hide the next one. Two shapes
are worth copying:

- **Kura instances are allowed by region, not by namespace.** The 11 orphans
  in #12467 sat in the `kura` namespace alongside dozens of live instances; a
  `kura/*` rule would have hidden them forever. Retiring a region is now a
  one-line deletion here, and its leftovers become findings on the next run.
- **`*.infrastructure.cluster.x-k8s.io` is not allowlisted**, even though the
  neighbouring CAPI groups are. That group is ours — its CRDs ship in
  `infra/helm/tuist/crds/` — so a CRD in it that `main` does not render is a
  real finding. The first run proved it: four abandoned CRDs.

## Adding a chart

When a workflow starts installing a chart into a managed cluster, add its row
to `releases.txt` in the same PR, with the release name and namespace matching
the `helm upgrade --install` exactly. A chart that is deployed but unlisted
makes every object it owns look orphaned.

That noise is the deliberate failure direction: it names the missing chart, in
a report a human reads, on the next run. The alternative — a check that
assumes coverage it does not have — fails the way the three orphans above did.

## Running it locally

Read-only, so the normal SSO kubeconfig is enough for most kinds. Note that
`customresourcedefinitions` is cluster-scoped: the `tuist-view-infra-read`
role grants it (see `infra/helm/pomerium/templates/access-tiers.yaml`), but a
plain upstream `view` binding does not, which is why CI uses the in-cluster
ServiceAccount kubeconfig instead.

```bash
KUBECTL_CONTEXT=tuist-k8s-production mise -C infra run k8s:orphan-drift-check production
```

Validate the config without a cluster (this is what runs on a pull request):

```bash
RENDER_ONLY=1 mise -C infra run k8s:orphan-drift-check all
```

Knobs: `KUBECTL_CONTEXT`, `MIN_AGE_HOURS`, `JSON_OUT`, `RELEASES_FILE`,
`ALLOWLIST_FILE`, `RENDER_ONLY`.

## Known gaps

- **Peer Services are matched by shape, not region.** The kura-controller
  creates `kura-<account>-peers` alongside each KuraInstance without an
  `ownerReference`, so they are allowlisted on name shape. A stranded
  region's Services are therefore not reported, only its KuraInstance — which
  is the object worth acting on, since deleting it reaps the rest. Setting an
  `ownerReference` on them in the controller would remove the rule entirely.
- **Namespaces created by `--create-namespace`** are outside their release by
  design and are allowlisted one by one. A new environment needs a new line.
- **Sibling repositories** (`tuist/once`, `tuist/condukt`) deploy into the
  production cluster from their own charts. The check renders nothing from
  them, so their namespaces are allowlisted whole.
