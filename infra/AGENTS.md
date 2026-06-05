# Infrastructure

Deployment assets for the Tuist stack — both the managed cluster we operate and the self-host chart our customers install.

## Layout

### `helm/tuist/` — main Tuist Helm chart
Umbrella chart for the server, cache, processor, auxiliary public server-owned workloads, and optional embedded infrastructure (Postgres, ClickHouse, object storage, observability). Used by:
- **Self-hosters** — `helm install tuist infra/helm/tuist` with their own `values.yaml`. `managedSecrets: false` (the default) keeps behavior self-hosted: DATABASE_URL / S3 / etc. come from values directly.
- **Managed cluster (us)** — layered with `values-managed-common.yaml` + `values-managed-{staging,canary,production}.yaml`. `managedSecrets: true` swaps the chart to ESO-driven secret sync from 1Password, external databases, Hetzner Cloud LoadBalancer annotations, etc.

When editing this chart, anything gated behind `managedSecrets` must stay gated so self-hosters aren't forced into the ESO dependency.

### `helm/noora-storybook/` — standalone Noora Storybook chart
Dedicated chart for the public `storybook.noora.tuist.dev` release. It deploys independently from the Tuist server so Noora Storybook changes do not have to share the server release boundary.

### `helm/slack/` — standalone Slack invitation chart
Dedicated chart for the public `slack.tuist.dev` release. It deploys independently from the Tuist server so Slack invitation-flow changes and operational state (SQLite PVC + ExternalSecret wiring) stay isolated from the main app release.

### `helm/k8s-monitoring/` — in-cluster Grafana Kubernetes Monitoring (managed only)
Wraps the upstream `grafana/k8s-monitoring` chart and adds the 1Password-via-ESO token sync. Ships the full Kubernetes telemetry picture (cluster / pod / node metrics + events + pod logs + OTLP receivers for managed workload traces, including server and Kura) to Grafana Cloud, so the Grafana Cloud Kubernetes app lights up without dashboard imports. Self-hosters get embedded Grafana / Prometheus / Loki / Tempo via the main chart's `observability.enabled` block instead; they never touch this chart.

README: [`helm/k8s-monitoring/README.md`](helm/k8s-monitoring/README.md).

### `helm/platform/` — platform bootstrap chart
cert-manager + external-dns + ESO + metrics-server controllers, installed once per workload cluster. ingress-nginx is enabled only on app-serving clusters; Kura regional clusters use direct `LoadBalancer` Services instead. Provider-specific LB annotations live in per-provider overlays (e.g., `values-hetzner.yaml`).

### `helm/tailscale-operator/` — Tailscale Kubernetes operator wrapper
Wraps the upstream `tailscale-operator` chart with ESO-synced OAuth credentials and per-env tag identity (`tag:tuist-k8s-<env>`). Provides three tailnet paths: a Connector subnet router (tailnet devices dial in-cluster Services), Mac mini egress (cluster Pods scrape the macOS fleet), and the API server proxy in auth mode for human kubectl access. In auth mode the proxy impersonates the caller's tailnet identity; tailnet ACL grants in [`tailscale/acls.json`](tailscale/acls.json) authorize impersonation and `accessBindings` maps the impersonated group to a built-in `ClusterRole`. Default tier on every env is **`view` for everyone (founders and engineers alike)**; writes go through the per-env `tuist-<env>-write` break-glass group managed by the JIT bot (see [Cluster access for agents](#cluster-access-for-agents) below). The proxy is additive: the public apiserver endpoint and the CI deployer kubeconfig are unaffected.

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

### `cnpg/` — CloudNativePG bootstrap SQL + Supabase→CNPG migration runbook
SQL files for per-table GRANTs that don't fit CNPG's `managed.roles[]` declarative surface (`tuist_processor` writes on Oban tables; `tuist_ops_ro` extras on top of `pg_read_all_data`). Also holds the end-to-end migration runbook for moving each managed env's Postgres from Supabase to the in-cluster CNPG cluster via logical replication. The actual `Cluster` / `ScheduledBackup` / ESO Secret manifests are rendered by the main Helm chart whenever `postgresql.cnpg.enabled` is true (provisioning + soak) or `postgresql.mode == "cnpg"` (cutover); this directory holds only the operator-run SQL + procedural docs that can't fit in the chart.

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

## Cluster access for agents

This section is normative for agents (Claude, Codex, anything driving `kubectl` on a teammate's behalf). The cluster-access design has a specific shape *because* of the agent threat model — read it before reaching for any escalation path.

### Default: read-only is always allowed, no setup needed

The team's tailnet identity carries through to every workload cluster via the Tailscale operator's API server proxy. From an agent running on a teammate's laptop, `kubectl --context tuist-k8s-<env>` works for any read operation: `get pods`, `logs`, `describe`, `get configmap`, `get events`. RBAC binds the impersonated identity to `view`, which **excludes `Secret`s** — that's deliberate, so `MASTER_KEY`, `DATABASE_URL`, and ESO-synced secrets stay out of agent context.

For anything an agent typically needs (looking at a failing pod, tailing logs, sanity-checking a deploy), this is the right path. Use it freely.

### Writes: never escalate without explicit human approval

Every mutating operation (`delete pod`, `apply -f`, `scale deployment`, `patch`, `create` of any kind) returns `403 Forbidden` by default. This is the agent-containment property the design protects — an agent with a teammate's tailnet identity cannot wreck a cluster silently.

The bot's `/elevate <env> [duration] <intent>` Slack flow is the path to write access. **It is not an agent-driven path.** The `Tuist.TailscaleJIT.Policy` module currently allows founders to self-approve any env and engineers to self-approve non-prod, but that policy assumes the click comes from a human at a keyboard. An agent that drives both `/elevate` and the Approve click via the same workstation's Slack token has defeated the entire design. Don't do it.

Concrete rules for agents:

- **Do not invoke `/elevate` autonomously.** If you think a write is needed, surface that to the human ("this would require elevation; can you run `/elevate ...` and grant the access?") and let them drive both the request and the approval.
- **Do not click Approve on any elevation request**, including (especially) one triggered by the human you're operating for. The "second human" attestation is meaningless if an agent is one of the two clicks.
- **Do not retrieve the 1Password admin kubeconfig.** `op document get "kubeconfig: tuist-<env>"` requires biometric on the local 1P CLI, which is the explicit friction that keeps an agent from silently fetching cluster-admin credentials. Asking the human to fetch it for you defeats that.
- **If the human has elevated themselves and you're now running inside that window**, mutating operations through the proxy will work — the elevation widens the *identity's* tier, not just the human's session. Treat the elevation as a scoped, time-bounded license to do exactly what was stated in the `intent` field of the request. Don't expand scope mid-session.

### Forensic trail

Every elevation produces records in four independent stores (Slack thread, the bot's Postgres tables, Tailscale's ACL audit log, the operator proxy's per-call access log in Grafana Cloud Loki). [`k8s/jit-elevation-audit.md`](k8s/jit-elevation-audit.md) is the runbook for joining them when something needs to be reconstructed.

### Where the bot lives

- Service code: [`server/lib/tuist/tailscale_jit/`](../server/lib/tuist/tailscale_jit/).
- Policy (self-approve + approver trust tiers): `Tuist.TailscaleJIT.Policy`. Both decisions read the requester's / approver's **tailnet role** (Owner / Admin / Member) from `GET /api/v2/tailnet/-/users` via `Tuist.TailscaleJIT.TailscaleClient.user_role/1`. There are no email lists in code; promoting someone in the Tailscale admin console Users page changes their bot policy on the next 30s cache tick.
- ACL source of truth: [`tailscale/acls.json`](tailscale/acls.json). The `src` selectors for cluster-proxy grants use `autogroup:owner` + `autogroup:admin` (cluster admins) and `autogroup:member` (engineers), so role changes in the console propagate without an ACL edit.
- Per-cluster RBAC: `accessBindings` in `helm/tailscale-operator/values-{staging,canary,production}.yaml`. The strings there (`tuist-admins`, `tuist-eng`) are the *Kubernetes-side* impersonation labels the operator injects on each forwarded request; they happen to share names with the historical tailnet groups for readability but live in a different system.

## Deployment

- **Tuist server** (managed) is deployed to our self-hosted CAPI Kubernetes clusters via the CI workflows:
  - `.github/workflows/server-deployment.yml` — build + deploy to one environment (workflow_dispatch or workflow_call).
  - `.github/workflows/server-production-deployment.yml` — cascade on push-to-main: canary → acceptance tests → production, with hotfix fast-path.
- **Noora Storybook** (managed) is deployed via `.github/workflows/noora-storybook-deployment.yml` using the standalone `infra/helm/noora-storybook` chart.
- **Slack invitation app** (managed) is deployed via `.github/workflows/slack-deployment.yml` using the standalone `infra/helm/slack` chart.
- **Registry Router** — `wrangler deploy` from `registry-router/`.
- **Helm charts** under `helm/` target Kubernetes (managed + self-hosted).

## Conventions

- Keep the main Tuist chart (`helm/tuist/`) provider-agnostic. Managed-cluster-specific behavior hides behind feature flags (`managedSecrets`, `externalSecrets`) that default to self-host-safe values.
- Don't let `helm/k8s-monitoring/` grow dependencies on things the self-host chart needs — the two are consumed by different users.
- When a new managed-cluster operational step becomes reproducible, document it in `k8s/onboarding.md` rather than in this AGENTS.md. This file maps the territory; the runbook walks you through it.
