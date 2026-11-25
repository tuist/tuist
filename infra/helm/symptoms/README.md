# symptoms chart

Deploys the [Symptoms](../../../symptoms/README.md) evaluator, its CNPG
PostgreSQL and the External Secrets that feed them, as release `symptoms` in
each workload cluster's `symptoms-<env>` namespace. Modelled on
[`tuist-ops`](../tuist-ops/README.md).

## What's in the box

- **Deployment**: one `ghcr.io/tuist/symptoms:<tag>` pod, `Recreate`. It
  migrates on boot unless `skipMigrations` is set. `decision.pagingEnabled`
  is the paging flag; production starts with paging off.
- **ServiceAccount** `symptoms`, with a projected token for the audience
  `tuist-symptoms-state` at `/var/run/secrets/tuist-symptoms-state/token`. The
  Tuist server verifies it with TokenReview against
  `TUIST_SYMPTOMS_EVALUATOR_NAMESPACE`/`_SERVICE_ACCOUNT`, so the namespace and
  ServiceAccount names are a contract with `server.symptoms` in the tuist
  chart.
- **ClusterRoles**: optional `get`, `list` and `watch` on `events` (core and
  `events.k8s.io`), and a separate `create tokenreviews` permission in
  `authentication.k8s.io`, independent of `eventsReader.enabled`.
- **Service**: ClusterIP for the server
  (`http://symptoms.symptoms-<env>.svc.cluster.local`), exposed on the tailnet
  as `symptoms-<env>` by the Tailscale operator. There is no Ingress.
- **NetworkPolicy** (in-cluster peers) and **CiliumNetworkPolicy** (DNS and the
  Kubernetes API, which a Kubernetes NetworkPolicy cannot name). Ingress: the Tuist server, the
  Tailscale proxy, and alloy-metrics for the metrics scrape. Egress: Pulse, the
  Tuist server, its own database, DNS and the Kubernetes API. No public HTTPS egress is allowed.
  The CNPG pods are not selected.
- **CNPG Cluster** `symptoms-pg`: two instances, daily backups to the
  environment's `tuist-<env>-pg-backups` bucket under `symptoms/`.
- **ExternalSecrets**: `symptoms-runtime` (below) and
  `symptoms-backup-credentials` (`S3_BACKUP_CREDENTIALS`, the item the server's
  CNPG cluster already uses).

## Runtime configuration

| Variable | Source |
| --- | --- |
| `DATABASE_URL` | CNPG `symptoms-pg-app` Secret, `uri` |
| `PHX_HOST`, `PORT`, `POOL_SIZE`, `SKIP_MIGRATIONS` | values |
| `SYMPTOMS_ENVIRONMENT` | `environment` |
| `SYMPTOMS_SERVER_NAMESPACE`, `SYMPTOMS_SERVER_SERVICE_ACCOUNT` | Required `tuist.namespace`, `tuist.serviceAccount`: the exact server principal allowed to call the evaluator API |
| `SYMPTOMS_PAGING_ENABLED`, `SYMPTOMS_LINK_BASE_URL` | `decision.pagingEnabled`, `decision.linkBaseUrl` (omitted when empty) |
| `SYMPTOMS_STATE_URL`, `SYMPTOMS_STATE_TOKEN_PATH` | `tuist.url`, the projected token |
| `SYMPTOMS_PULSE_URL`, `SYMPTOMS_PULSE_USER` | `pulse.url`, `pulse.username` (read-only `dashboard`) |
| `SYMPTOMS_PULSE_TOKEN` | `PULSE_TOKEN/password` (`pulse.tokenItem`/`tokenField`) |
| `SYMPTOMS_PULSE_WRITE_USER` | `pulse.writeUsername` (write-only `tuist`), for the hourly span-edge INSERT |
| `SYMPTOMS_PULSE_WRITE_TOKEN` | `PULSE_TOKEN/password` (`pulse.writeTokenItem`/`writeTokenField`): Pulse's `tuist:wo` identity shares the dashboard password |
| `SYMPTOMS_PROMETHEUS_URL` | `pulse.url` + `/v1/prometheus` (Pulse's Prometheus-compatible API, database `public`) |
| `SYMPTOMS_PROMETHEUS_USER`, `SYMPTOMS_PROMETHEUS_TOKEN` | `pulse.username`, the existing read-only `PULSE_TOKEN/password` |

IRM integration is deferred. The chart mounts no IRM credentials and paging stays disabled.

Keep this table in sync with `symptoms/config/runtime.exs`.

The evaluator uses its normal mounted Kubernetes API token and CA to submit
TokenReview requests with the fixed audience `tuist-symptoms-api`. The server
presents a pod-bound projected token with a 3600-second lifetime. Managed values
allow `tuist-server` in `tuist-staging`, `tuist-canary`, or `tuist`, depending
on the environment. A custom server release or `server.serviceAccount.name`
requires matching `tuist.serviceAccount` here; changing namespaces requires
matching `tuist.namespace`. Do not allow a namespace-wide group. The separate
`tuist-symptoms-state` projection and server-side evaluator allowlist remain in use.

## Before the first deploy

1. Set `tuist.namespace` and `tuist.serviceAccount` to the server Pod's exact
   principal. The API-only evaluator uses no shared API token, sessions or signing
   key. Keep the existing `PULSE_TOKEN/password` for telemetry reads and writes.
2. Let the evaluator reach Pulse: Pulse's `pulse-private` NetworkPolicy
   (`infra/helm/pulse`) admits only the observability namespace and the Tuist
   server today, so add an ingress rule for `symptoms-<env>` pods
   (`app.kubernetes.io/name: symptoms`) on port 4000.
3. Confirm the `S3_BACKUP_CREDENTIALS` keys may write `symptoms/` in each
   environment's backup bucket.
4. Deploy with `.github/workflows/symptoms-deployment.yml`, then turn on
   `server.symptoms.enabled` in the tuist chart's managed values.

## Image and deploy

`.github/workflows/symptoms-deployment.yml` builds
`ghcr.io/tuist/symptoms:sha-<12>` (context `symptoms/`, with
`infra/certificate-trust` as the `certificate-trust` build context) and deploys
staging, canary, then production, each behind its `server-k8s-<env>`
environment. Pull requests only validate the chart and build the image.

Local render:

```bash
helm template symptoms infra/helm/symptoms -n symptoms-production \
  -f infra/helm/symptoms/values-production.yaml -f infra/helm/symptoms/values-ci.yaml
```

Roll back one environment by dispatching the workflow with that environment and
an earlier `image_tag`.
