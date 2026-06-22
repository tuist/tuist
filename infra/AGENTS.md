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
cert-manager + external-dns + ESO + metrics-server + ingress-nginx controllers, installed once per workload cluster. Kura customer endpoints default to dedicated shared regional Kura ingress controllers rather than the main web ingress dataplane. Enterprise/high-volume exceptions are reconciled dynamically by the Kura controller from `KuraGateway` CRs, not hard-coded as customer-specific platform chart aliases. Provider-specific LB annotations live in per-provider and cluster overlays (e.g., `values-hetzner.yaml`, `values-tuist.yaml`).

### `helm/tailscale-operator/` — Tailscale Kubernetes operator wrapper
Wraps the upstream `tailscale-operator` chart with ESO-synced OAuth credentials and per-env tag identity (`tag:tuist-k8s-<env>`). Provides two tailnet paths used today: a Connector subnet router (tailnet devices dial in-cluster Services) and Mac mini egress (cluster Pods scrape the macOS fleet). Human kubectl access to workload clusters does NOT flow through the operator's API-server proxy anymore — see `helm/pomerium/` below.

### `helm/pomerium/` — kubectl gateway, one per workload cluster
Self-contained chart (NOT a wrapper around upstream's split-mode `pomerium/pomerium` — too heavy for our scale; one binary in all-in-one mode covers our 5-human team). One Helm release per workload env (staging / canary / production) deployed into that cluster. Pomerium fronts `https://kube-<env>.tuist.dev` and authenticates humans via Google Workspace OIDC. Per-request impersonation injection is handled by the `kube-impersonator` sidecar in the same pod (see [`kube-impersonator/`](../kube-impersonator/)) — Pomerium forwards every kubectl call to the sidecar, the sidecar calls tuist-ops's `/api/v1/policy` over the tailnet, the policy returns `Impersonate-User` + `Impersonate-Group` response headers, the sidecar attaches them plus the pod SA bearer to the upstream request, and the apiserver RBAC-binds the impersonated group to a built-in `ClusterRole`. ClusterRoleBindings for `tuist-admins / tuist-eng / tuist-<env>-write` ship in this chart (`templates/access-tiers.yaml`). Default tier is **`view` for everyone (founders and engineers alike)**; elevated `edit` access flows through the JIT Slack flow (see [Cluster access for agents](#cluster-access-for-agents) below). The sidecar reaches tuist-ops over the tailnet via a `tailscale.com/tailnet-fqdn`-annotated egress Service.

### `helm/tuist-ops/` — internal ops Phoenix app
Single-replica deploy of the `tuist-ops` app into the production cluster (same cluster as `server/` and `slack/`; matches the "internal Tuist-team tooling lives alongside customer workload" pattern). Hosts the JIT elevation Slack bot (`/webhooks/slack/*`) and the impersonation policy endpoint (`/api/v1/policy`) called by each env's `kube-impersonator` sidecar. Public ingress on `ops.tuist.dev` routes ONLY the Slack-signed webhook paths to the upstream; everything else is reachable solely on the tailnet as `ops.<tailnet>.ts.net` via a `tailscale.com/expose: true` Service (Pomerium pods in all envs cross-call here through their `tuist-ops-egress` Service). Includes its own CNPG Cluster in the production cluster (3-table schema, ~5Gi storage, daily Tigris backups). Decoupled from `server/` at the deploy / namespace / chart level so customer-facing changes can roll independently of internal-ops changes.

### `k8s/` — CAPI cluster manifests
Cluster API CRs and cluster-scoped manifests for the self-hosted CAPI + caph stack we operate on Hetzner:
- `clusters/clusterclass-tuist.yaml` — the `tuist-hcloud` ClusterClass (HA control plane, worker-pool variables, network config, kubeadm + kubelet config).
- `clusters/cluster-{staging,canary,production,preview}.yaml` — per-env Cluster CRs in topology mode.
- Production Kura regions are node pools in `clusters/cluster-production.yaml`, not separate workload clusters.
- The preview cluster also hosts Slack-requested preview environments:
  app workloads and preview Kura runtime pods both land on the tainted
  preview worker pool (`role=preview`, with the preview toleration on the
  KuraInstance). The Kura controller itself runs once cluster-wide in the
  `kura` namespace; each preview's `KuraInstance` is created there.
- `clusters/README.md` — ClusterClass authoring + caph-upstream porting notes.
- `mgmt/cluster-autoscaler.yaml`, `mgmt/etcd-snapshot.yaml`, `mgmt/tailscale.yaml` — mgmt-cluster workloads (Cluster API node autoscaling for managed Kura/app clusters, hourly etcd snapshot to Tigris, tailnet-only operator access).
- `mgmt/bootstrap/` — Helm values for the per-workload bootstrap (Cilium, HCCM, hcloud-csi, ESO `ClusterSecretStore`).
- `mgmt/ci-service-account.yaml` — SA + RBAC for the GitHub Actions deployer (applied per workload).
- `mgmt/preview-mgmt-rbac.yaml` — narrow SA + Role on the mgmt cluster used by the preview-deploy / preview-sweep workflows to scale the preview MachineDeployment.
- `onboarding.md` — end-to-end runbook for standing up a new workload cluster.

### `kura-controller/` — Kura endpoint controller
Go controller for `KuraInstance` and `KuraGateway` CRs (`kura.tuist.dev/v1alpha1`). It reconciles account-region Kura endpoint intent into Kubernetes workload resources and, when server policy requests it, dedicated ingress-nginx/LB gateway infrastructure on the Hetzner-backed cluster. Keep it separate from CAPI infrastructure providers; it manages product workload lifecycle, not cluster node lifecycle.

### `registry-router/` — Cloudflare Worker for `registry.tuist.dev`
Geo-routes cache registry requests to the nearest healthy cache origin based on the requester's continent. Unrelated to the Kubernetes migration.

### `cnpg/` — CloudNativePG bootstrap SQL
SQL files for per-table GRANTs that don't fit CNPG's `managed.roles[]` declarative surface (`tuist_processor` writes on Oban tables; `tuist_ops_ro` extras on top of `pg_read_all_data`). The actual `Cluster` / `ScheduledBackup` / ESO Secret manifests are rendered by the main Helm chart whenever `postgresql.cnpg.enabled` is true or `postgresql.mode == "cnpg"`; this directory holds only the operator-run SQL that can't fit in the chart.

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

The team's Google Workspace identity carries through to every workload cluster via Pomerium fronting `https://kube-<env>.tuist.dev`. From an agent running on a teammate's laptop, `kubectl --context tuist-k8s-<env>` works for any read operation: `get pods`, `logs`, `describe`, `get configmap`, `get events`, `get nodes`, the cluster-scoped infra CRs (`scalewayelasticmetalmachines`, `machinedeployments`, `kurainstances`, `customresourcedefinitions`), and RBAC objects (`get clusterrole`, `get rolebinding`) for diagnosing authorization. The `pomerium-cli` exec credential plugin handles the bearer; the teammate's existing browser-cached session is used silently. Each request then flows through the `kube-impersonator` sidecar in the Pomerium pod, which calls tuist-ops's `/api/v1/policy` over the tailnet; the policy returns `Impersonate-User: <email>` + `Impersonate-Group: tuist-eng` (or `tuist-admins` for Owner/Admin tailnet roles). RBAC binds those groups to `view`, which **excludes `Secret`s** — deliberate, so `MASTER_KEY`, `DATABASE_URL`, and ESO-synced secrets stay out of agent context. The upstream `view` role also omits cluster-scoped and custom resources, so the `tuist-view-infra-read` aggregated ClusterRole (in [`helm/pomerium/templates/access-tiers.yaml`](helm/pomerium/templates/access-tiers.yaml)) extends it with `get`/`list`/`watch` on `nodes`, CAPI machines (`cluster.x-k8s.io`, `infrastructure.cluster.x-k8s.io`), Kura CRs (`kura.tuist.dev`), CRDs, and RBAC objects (`rbac.authorization.k8s.io`). It aggregates into `view` via a label (no extra binding) and adds no `Secret` rule, so the exclusion above is unaffected. RBAC read is the one deliberate departure from upstream `view` (which hides the authz graph as anti-recon); accepted here because containment is on mutation, not reads, and it lets agents diagnose a misbound/`NotFound` RBAC object during a deploy.

For anything an agent typically needs (looking at a failing pod, tailing logs, sanity-checking a deploy), this is the right path. Use it freely. The one-time local kubeconfig setup (install `pomerium-cli`, merge the three per-env contexts) is in [`k8s/onboarding.md` → Engineer read access](k8s/onboarding.md#engineer-read-access-pomerium-kubeconfig).

### Writes: never escalate without explicit human approval

Every mutating operation (`delete pod`, `apply -f`, `scale deployment`, `patch`, `create` of any kind) returns `403 Forbidden` by default. This is the agent-containment property the design protects — an agent with a teammate's Pomerium session cannot wreck a cluster silently.

The bot's `/elevate <env> [duration] <intent>` Slack flow is the path to write access. **It is not an agent-driven path.** `TuistOps.JIT.Policy` currently allows Owner/Admin tailnet roles to self-approve any env and Member to self-approve non-prod, but that policy assumes the click comes from a human at a keyboard. An agent that drives both `/elevate` and the Approve click via the same workstation's Slack token has defeated the entire design. Don't do it.

Concrete rules for agents:

- **Do not invoke `/elevate` autonomously.** If you think a write is needed, surface that to the human ("this would require elevation; can you run `/elevate ...` and grant the access?") and let them drive both the request and the approval.
- **Do not click Approve on any elevation request**, including (especially) one triggered by the human you're operating for. The "second human" attestation is meaningless if an agent is one of the two clicks.
- **Do not retrieve the 1Password admin kubeconfig.** `op document get "kubeconfig: tuist-<env>"` requires biometric on the local 1P CLI, which is the explicit friction that keeps an agent from silently fetching cluster-admin credentials. Asking the human to fetch it for you defeats that.
- **If the human has elevated themselves and you're now running inside that window**, mutating operations will succeed — tuist-ops's policy response adds the env's write group to the impersonation headers, widening the *identity's* tier, not just the human's session. Treat the elevation as a scoped, time-bounded license to do exactly what was stated in the `intent` field of the request. Don't expand scope mid-session.

### Forensic trail

Every elevation produces records in three independent stores:
- **Slack thread** in `#tailscale-jit-approvals` (request → approval → outcome).
- **tuist-ops Postgres** (`tailscale_jit_requests` + `tailscale_jit_elevations`).
- **Pomerium access log** in Grafana Cloud Loki — one line per kubectl call with `user_email`, `method`, `path`, `response_code`, joined-on-elevation via the active row at request time.

The previous "Tailscale ACL audit log" trail no longer applies — the ACL is now a static, code-reviewed document; the bot does not mutate it at runtime.

### Where the bot lives

- Service code: [`tuist-ops/lib/tuist_ops/jit/`](../tuist-ops/lib/tuist_ops/jit/) (the standalone Phoenix app in [`tuist-ops/`](../tuist-ops/)).
- Policy (self-approve + approver trust tiers): `TuistOps.JIT.Policy`. Both decisions read the requester's / approver's **tailnet role** (Owner / Admin / Member) from `GET /api/v2/tailnet/-/users` via `TuistOps.JIT.TailscaleClient.user_role/1`. There are no email lists in code; promoting someone in the Tailscale admin console Users page changes their bot policy on the next 30s cache tick.
- Per-call impersonation resolution: `TuistOpsWeb.PolicyController` is the HTTP endpoint each env's `kube-impersonator` sidecar dials on every kubectl request. Reads the active Elevation row for `(subject, env)` and returns `Impersonate-User` / `Impersonate-Group` response headers; the sidecar copies them onto the upstream request to the apiserver.
- Tailnet ACL: [`tailscale/acls.json`](tailscale/acls.json). View-tier only; static; humans edit it through code review. The `tuist-admins` / `tuist-eng` / `tuist-<env>-write` strings are *Kubernetes-side* impersonation labels, bound to ClusterRoles by `infra/helm/pomerium/templates/access-tiers.yaml`.

## Deployment

- **Tuist server** (managed) is deployed to our self-hosted CAPI Kubernetes clusters via the CI workflows:
  - `.github/workflows/server-deployment.yml` — build + deploy to one environment (workflow_dispatch or workflow_call).
  - `.github/workflows/server-production-deployment.yml` — the monorepo release pipeline (push-on-main): releases the server + fleet/runtime images and, at its tail, runs the production deploy cascade (build → canary → acceptance tests → production, with hotfix fast-path). One serialized lane, no cross-workflow dispatch. Manual re-promotes/rollbacks of a pinned SHA go through `server-deployment.yml`'s own `workflow_dispatch`.
- **Noora Storybook** (managed) is deployed via `.github/workflows/noora-storybook-deployment.yml` using the standalone `infra/helm/noora-storybook` chart.
- **Slack invitation app** (managed) is deployed via `.github/workflows/slack-deployment.yml` using the standalone `infra/helm/slack` chart.
- **Registry Router** — `wrangler deploy` from `registry-router/`.
- **Helm charts** under `helm/` target Kubernetes (managed + self-hosted).

## Conventions

- Keep the main Tuist chart (`helm/tuist/`) provider-agnostic. Managed-cluster-specific behavior hides behind feature flags (`managedSecrets`, `externalSecrets`) that default to self-host-safe values.
- Don't let `helm/k8s-monitoring/` grow dependencies on things the self-host chart needs — the two are consumed by different users.
- When a new managed-cluster operational step becomes reproducible, document it in `k8s/onboarding.md` rather than in this AGENTS.md. This file maps the territory; the runbook walks you through it.
