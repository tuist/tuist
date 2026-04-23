# Infrastructure

Deployment assets for the Tuist stack — both the managed cluster we operate and the self-host chart our customers install.

## Layout

### `helm/tuist/` — main Tuist Helm chart
Umbrella chart for the server, cache, processor, and optional embedded infrastructure (Postgres, ClickHouse, object storage, observability). Used by:
- **Self-hosters** — `helm install tuist infra/helm/tuist` with their own `values.yaml`. `managedSecrets: false` (the default) keeps behavior self-hosted: DATABASE_URL / S3 / etc. come from values directly.
- **Managed cluster (us)** — layered with `values-managed-common.yaml` + `values-managed-{staging,canary,production}.yaml`. `managedSecrets: true` swaps the chart to ESO-driven secret sync from 1Password, external databases, Hetzner Cloud LoadBalancer annotations, etc.

When editing this chart, anything gated behind `managedSecrets` must stay gated so self-hosters aren't forced into the ESO dependency.

### `helm/alloy/` — in-cluster Grafana Alloy (managed only)
Ships telemetry (metrics / traces / logs) from the managed workload clusters to Grafana Cloud. Self-hosters get embedded Grafana / Prometheus / Loki / Tempo via the main chart's `observability.enabled` block instead; they never touch this chart.

README: [`helm/alloy/README.md`](helm/alloy/README.md).

### `helm/platform/` — platform bootstrap chart
cert-manager + ingress-nginx + external-dns + ESO controllers, installed once per workload cluster. Provider-specific LB annotations live in per-provider overlays (e.g., `values-hetzner.yaml`).

### `k8s/` — Syself Apalla cluster manifests
Cluster API CRs and cluster-scoped manifests that stand up our managed Kubernetes clusters on Hetzner via Syself Apalla:
- `syself/workload-cluster-{staging,canary,production}.yaml` — per-env Cluster CRs (control plane + worker shape, region, k8s version).
- `syself/cluster-stack.yaml` — ClusterStack subscription (controls which k8s version + node image build we use).
- `syself/ci-service-account.yaml` — SA + RBAC for the GitHub Actions deployer.
- `syself/ingress-nginx-values.yaml` — Helm values with Hetzner LB annotations (for a future ingress-nginx-based setup; not installed today).
- `syself-onboarding.md` — end-to-end runbook for standing up a new workload cluster.
- `provider-evaluation.md` — historical record of the provider decision (Syself vs. GKE etc.).

### `registry-router/` — Cloudflare Worker for `registry.tuist.dev`
Geo-routes cache registry requests to the nearest healthy cache origin based on the requester's continent. Unrelated to the Kubernetes migration.

## Deployment

- **Tuist server** (managed) is deployed to our Syself Kubernetes clusters via the CI workflows:
  - `.github/workflows/server-deployment.yml` — build + deploy to one environment (workflow_dispatch or workflow_call).
  - `.github/workflows/server-production-deployment.yml` — cascade on push-to-main: canary → acceptance tests → production, with hotfix fast-path.
- **Registry Router** — `wrangler deploy` from `registry-router/`.
- **Helm charts** under `helm/` target Kubernetes (managed + self-hosted).

## Conventions

- Keep the main Tuist chart (`helm/tuist/`) provider-agnostic. Managed-cluster-specific behavior hides behind feature flags (`managedSecrets`, `externalSecrets`) that default to self-host-safe values.
- Don't let `helm/alloy/` grow dependencies on things the self-host chart needs — the two are consumed by different users.
- When a new managed-cluster operational step becomes reproducible, document it in `k8s/syself-onboarding.md` rather than in this AGENTS.md. This file maps the territory; the runbook walks you through it.
