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
- **ClusterRole** with `get`, `list` and `watch` on `events` (core and
  `events.k8s.io`) in every namespace, and nothing else.
- **Service**: ClusterIP for the server
  (`http://symptoms.symptoms-<env>.svc.cluster.local`), exposed on the tailnet
  as `symptoms-<env>` by the Tailscale operator. There is no Ingress.
- **NetworkPolicy** (in-cluster peers) and **CiliumNetworkPolicy** (DNS, the
  Kubernetes API, and `*.grafana.net` by host name, which
  a Kubernetes NetworkPolicy cannot express). Ingress: the Tuist server, the
  Tailscale proxy, and alloy-metrics for the metrics scrape. Egress: Pulse, the
  Tuist server, its own database, DNS, the Kubernetes API and Grafana Cloud.
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
| `SECRET_KEY_BASE` | `SYMPTOMS/secret_key_base` |
| `PHX_HOST`, `PORT`, `POOL_SIZE`, `SKIP_MIGRATIONS` | values |
| `SYMPTOMS_ENVIRONMENT` | `environment` |
| `SYMPTOMS_API_TOKEN` | `SYMPTOMS/api_token`, the bearer token of the evaluator API; the server reads the same field |
| `SYMPTOMS_PAGING_ENABLED`, `SYMPTOMS_LINK_BASE_URL` | `decision.pagingEnabled`, `decision.linkBaseUrl` (omitted when empty) |
| `SYMPTOMS_IRM_WEBHOOK_URL` | `SYMPTOMS/irm_webhook_url` (may be empty while paging is off) |
| `SYMPTOMS_STATE_URL`, `SYMPTOMS_STATE_TOKEN_PATH` | `tuist.url`, the projected token |
| `SYMPTOMS_PULSE_URL`, `SYMPTOMS_PULSE_USER` | `pulse.url`, `pulse.username` (read-only `dashboard`) |
| `SYMPTOMS_PULSE_TOKEN` | `PULSE_TOKEN/password` (`pulse.tokenItem`/`tokenField`) |
| `SYMPTOMS_PULSE_WRITE_USER` | `pulse.writeUsername` (write-only `tuist`), for the hourly span-edge INSERT |
| `SYMPTOMS_PULSE_WRITE_TOKEN` | `PULSE_TOKEN/password` (`pulse.writeTokenItem`/`writeTokenField`): Pulse's `tuist:wo` identity shares the dashboard password |
| `SYMPTOMS_PROMETHEUS_URL` | `prometheus.url` (Grafana Cloud) |
| `SYMPTOMS_PROMETHEUS_USER`, `SYMPTOMS_PROMETHEUS_TOKEN` | `SYMPTOMS/grafana_cloud_metrics_user`, `SYMPTOMS/grafana_cloud_metrics_read_token` |

The optional `SYMPTOMS_IRM_WEBHOOK_TOKEN` is not set by the chart.

Keep this table in sync with `symptoms/config/runtime.exs`.

## Before the first deploy

1. Create the `SYMPTOMS` item in each `tuist-k8s-<env>` vault with the fields
   `api_token`, `secret_key_base` (`mix phx.gen.secret`), `irm_webhook_url`
   (may be empty), `grafana_cloud_metrics_user` (the Prometheus instance ID) and
   `grafana_cloud_metrics_read_token` (an access policy token with
   `metrics:read`). The Pulse passwords come from the existing
   `PULSE_TOKEN/password`.
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
