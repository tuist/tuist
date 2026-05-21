# Infrastructure

Deployment assets for the Tuist stack — both the managed cluster we operate and the self-host chart our customers install.

## Layout

### `helm/tuist/` — main Tuist Helm chart
Umbrella chart for the server, cache, processor, and optional embedded infrastructure (Postgres, ClickHouse, object storage, observability). Used by:
- **Self-hosters** — `helm install tuist infra/helm/tuist` with their own `values.yaml`. `managedSecrets: false` (the default) keeps behavior self-hosted: DATABASE_URL / S3 / etc. come from values directly.
- **Managed cluster (us)** — layered with `values-managed-common.yaml` + `values-managed-{staging,canary,production}.yaml`. `managedSecrets: true` swaps the chart to ESO-driven secret sync from 1Password, external databases, Hetzner Cloud LoadBalancer annotations, etc.

When editing this chart, anything gated behind `managedSecrets` must stay gated so self-hosters aren't forced into the ESO dependency.

### `helm/k8s-monitoring/` — in-cluster Grafana Kubernetes Monitoring (managed only)
Wraps the upstream `grafana/k8s-monitoring` chart and adds the 1Password-via-ESO token sync. Ships the full Kubernetes telemetry picture (cluster / pod / node metrics + events + pod logs + OTLP receivers for managed workload traces, including server and Kura) to Grafana Cloud, so the Grafana Cloud Kubernetes app lights up without dashboard imports. Self-hosters get embedded Grafana / Prometheus / Loki / Tempo via the main chart's `observability.enabled` block instead; they never touch this chart.

README: [`helm/k8s-monitoring/README.md`](helm/k8s-monitoring/README.md).

### `helm/platform/` — platform bootstrap chart
cert-manager + external-dns + ESO controllers, installed once per workload cluster. ingress-nginx is enabled only on app-serving clusters; Kura regional clusters use direct `LoadBalancer` Services instead. Provider-specific LB annotations live in per-provider overlays (e.g., `values-hetzner.yaml`).

### `k8s/` — CAPI cluster manifests
Cluster API CRs and cluster-scoped manifests for the self-hosted CAPI + caph stack we operate on Hetzner:
- `clusters/clusterclass-tuist.yaml` — the `tuist-hcloud` ClusterClass (HA control plane, worker-pool variables, network config, kubeadm + kubelet config).
- `clusters/cluster-{staging,canary,production,preview}.yaml` — per-env Cluster CRs in topology mode.
- `clusters/cluster-production-us-{east,west}.yaml` — production Kura regional workload clusters mapped to Hetzner `ash` / `hil`.
- `clusters/README.md` — ClusterClass authoring + caph-upstream porting notes.
- `mgmt/etcd-snapshot.yaml`, `mgmt/tailscale.yaml` — mgmt-cluster workloads (hourly etcd snapshot to Tigris, tailnet-only operator access).
- `mgmt/bootstrap/` — Helm values for the per-workload bootstrap (Cilium, HCCM, hcloud-csi, ESO `ClusterSecretStore`).
- `mgmt/ci-service-account.yaml` — SA + RBAC for the GitHub Actions deployer (applied per workload).
- `mgmt/preview-mgmt-rbac.yaml` — narrow SA + Role on the mgmt cluster used by the preview-deploy / preview-sweep workflows to scale the preview MachineDeployment.
- `onboarding.md` — end-to-end runbook for standing up a new workload cluster.

### `kura-controller/` — Kura endpoint controller
Go controller for `KuraInstance` CRs (`kura.tuist.dev/v1alpha1`). It reconciles account-region Kura endpoint intent into Kubernetes workload resources on the Hetzner-backed cluster. Keep it separate from CAPI infrastructure providers; it manages product workload lifecycle, not cluster node lifecycle.

### `registry-router/` — Cloudflare Worker for `registry.tuist.dev`
Geo-routes cache registry requests to the nearest healthy cache origin based on the requester's continent. Unrelated to the Kubernetes migration.

### `vm-image-builder.md` — bare-metal builder fleet operator runbook
End-to-end runbook for the bare-metal Mac mini fleet that bakes our Tart VM images (runner-image, xcresult-processor-image). Cluster-managed via the same CAPI provider that runs the other macOS fleets; hosts are regular Nodes with tart-kubelet idle plus a GitHub Actions self-hosted runner installed on top via the `ScalewayAppleSiliconMachineSpec.GHActionsRunner` sub-spec. Scale by editing `buildersFleet.replicas` or `kubectl scale machinedeployment`.

### `grafana-dashboards/` — Grafana Cloud dashboards (managed only)
Dashboard definitions synced with Grafana Cloud via [Git Sync](https://grafana.com/docs/grafana-cloud/as-code/observability-as-code/git-sync/). The `Tuist Dashboards` folder in Grafana Cloud is bound to this directory; changes propagate in both directions.

Each file is a `dashboard.grafana.app/v1` resource. The raw dashboard JSON lives under `spec`; the wrapper (`apiVersion`, `kind`, `metadata.name`) is what Grafana Git Sync expects. `metadata.name` must match the dashboard UID.

**Editing workflow:**
- Prefer editing dashboards in the Grafana UI. On save, Grafana opens a pull request against `tuist/tuist` with the updated file. Direct commits to `main` from Grafana are disabled, so every UI save goes through PR review.
- Editing files directly in the repo is also supported: after merge, Grafana pulls on its sync interval (60s) or via webhook.
- **Adding a new dashboard:** create it in the `Tuist Dashboards` folder in Grafana Cloud (or move an existing unmanaged dashboard into it). The save dialog opens a PR with the wrapped file; merging it provisions the dashboard back.
- **Self-host use:** self-hosters who just want to import one of these into their own Grafana should extract the `spec` first (e.g. `jq '.spec' cache-service.json > dashboard.json`), since the Grafana Import UI expects raw dashboard JSON rather than the resource wrapper.

## Deployment

- **Tuist server** (managed) is deployed to our self-hosted CAPI Kubernetes clusters via the CI workflows:
  - `.github/workflows/server-deployment.yml` — build + deploy to one environment (workflow_dispatch or workflow_call).
  - `.github/workflows/server-production-deployment.yml` — cascade on push-to-main: canary → acceptance tests → production, with hotfix fast-path.
- **Registry Router** — `wrangler deploy` from `registry-router/`.
- **Helm charts** under `helm/` target Kubernetes (managed + self-hosted).

## Conventions

- Keep the main Tuist chart (`helm/tuist/`) provider-agnostic. Managed-cluster-specific behavior hides behind feature flags (`managedSecrets`, `externalSecrets`) that default to self-host-safe values.
- Don't let `helm/k8s-monitoring/` grow dependencies on things the self-host chart needs — the two are consumed by different users.
- When a new managed-cluster operational step becomes reproducible, document it in `k8s/onboarding.md` rather than in this AGENTS.md. This file maps the territory; the runbook walks you through it.
