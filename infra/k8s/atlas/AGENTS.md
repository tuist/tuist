# Infrastructure

Deployment assets for Atlas. Single managed environment (`production`)
on Hetzner, reconciled by the self-hosted CAPI + caph management
cluster (`tuist-mgmt`) maintained in tuist/tuist.

## Layout

### `helm/atlas/` — Atlas Helm chart
Phoenix Deployment, Service, Ingress (cert-manager + external-dns),
HPA, PDB, pre-install/upgrade migration Job, ServiceAccount, plus an
in-cluster CloudNativePG `Cluster` with continuous backups to Hetzner
Object Storage.

**Secrets model.** Every secret is its own item in the
`atlas-k8s-production` 1Password vault. ESO (external-secrets-operator)
syncs them into a single `atlas-app` Secret which the Deployment +
migration Job consume via `envFrom`. Operator-level credentials the app
never sees (CNPG backup creds, GHCR pull token) are also synced from
their own 1P items. The vault is reached through a per-environment
1Password Service Account with read-only access to that vault — the
same pattern tuist/tuist uses.

The chart is **managed-only** — there is no `selfHosted` toggle. If
self-host ever becomes a target, fork.

### `k8s/` — cluster + CI manifests
- `cluster-production.yaml` — Cluster API CR (topology mode against
  tuist/tuist's `tuist-hcloud` ClusterClass) for the atlas workload
  cluster on Hetzner, fsn1.
- `ci-service-account.yaml` — namespaced SA + cluster-admin binding
  used by the GitHub Actions deployer.
- `onboarding.md` — end-to-end runbook for standing up everything
  from scratch.

## Deployment

- `.github/workflows/deploy.yml` builds `ghcr.io/tuist/atlas:sha-<short>`
  on push-to-main and runs `helm upgrade --install --atomic`.
- Cluster bootstrap (cert-manager / ingress-nginx / external-dns / ESO /
  CloudNativePG) is one-time and lives in `k8s/onboarding.md`.

## Conventions

- Reproducible cluster operations get added to `k8s/onboarding.md`.
  This file is for orientation; the runbook is for action.
- Secrets never go through `--set` or values files — only ESO.
- The image is private (GHCR); the pull secret is also ESO-synced from
  a 1Password item that holds a base64-encoded dockerconfigjson.
