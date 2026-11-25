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
  Tailscale proxy (API port only), and alloy-metrics on the separate metrics
  port, which the Service does not expose. Egress: Pulse, the
  Tuist server, its own database, DNS and the Kubernetes API. No public HTTPS egress is allowed.
  The CNPG pods are not selected.
- **CNPG Cluster** `symptoms-pg`: two instances, daily backups to the
  environment's `tuist-<env>-pg-backups` bucket under `symptoms/`.
- **ExternalSecrets**: `symptoms-runtime` (below) and
  `symptoms-backup-credentials` (`SYMPTOMS_PG_BACKUP`, a key scoped to the
  `symptoms/` prefix; see "Backup key").

## Runtime configuration

| Variable | Source |
| --- | --- |
| `DATABASE_URL` | CNPG `symptoms-pg-app` Secret, `uri` |
| `PHX_HOST`, `PORT`, `POOL_SIZE`, `SKIP_MIGRATIONS` | values |
| `SYMPTOMS_ENVIRONMENT` | `environment` |
| `SYMPTOMS_SERVER_NAMESPACE`, `SYMPTOMS_SERVER_SERVICE_ACCOUNT` | Required `tuist.namespace`, `tuist.serviceAccount`: the exact server principal allowed to call the evaluator API |
| `SYMPTOMS_METRICS_PORT` | `metrics.port`, the scrape-only listener (`metrics.enabled`) |
| `SYMPTOMS_PAGING_ENABLED`, `SYMPTOMS_LINK_BASE_URL` | `decision.pagingEnabled`, `decision.linkBaseUrl` (omitted when empty) |
| `SYMPTOMS_STATE_URL`, `SYMPTOMS_STATE_TOKEN_PATH` | `tuist.url`, the projected token |
| `SYMPTOMS_PULSE_URL`, `SYMPTOMS_PULSE_USER` | `pulse.url`, `pulse.username` (read-only `symptoms`) |
| `SYMPTOMS_PULSE_TOKEN` | `PULSE_SYMPTOMS_READER/password` (`pulse.tokenItem`/`tokenField`). Never `PULSE_TOKEN`, which is also the collectors' write password |
| `SYMPTOMS_PROMETHEUS_URL` | `pulse.url` + `/v1/prometheus` (Pulse's Prometheus-compatible API, database `public`) |
| `SYMPTOMS_PROMETHEUS_USER`, `SYMPTOMS_PROMETHEUS_TOKEN` | `pulse.username` and the same `PULSE_SYMPTOMS_READER/password` |

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

These are human steps; nothing in CI or an agent session does them.

1. Set `tuist.namespace` and `tuist.serviceAccount` to the server Pod's exact
   principal. The API-only evaluator uses no shared API token, sessions or signing
   key.
2. Give the evaluator its own Pulse reader: create `PULSE_SYMPTOMS_READER` in
   each vault with a `password` field of letters and digits only, add the
   environment to `symptomsReader.environments` in `infra/helm/pulse/values.yaml`
   and deploy Pulse (it restarts the frontends, which load users at startup).
   The evaluator reads as `symptoms:ro`; it never gets `PULSE_TOKEN`, which is
   also the collectors' `tuist:wo` password. Pulse's `pulse-private`
   NetworkPolicy already admits the evaluator on port 4000.
3. Create the backup key below and store it as `SYMPTOMS_PG_BACKUP`.
4. Deploy with `.github/workflows/symptoms-deployment.yml`, then turn on
   `server.symptoms.enabled` in the tuist chart's managed values.

## Backup key

The evaluator's CNPG cluster archives to `s3://tuist-<env>-pg-backups/symptoms`
with a Tigris key of its own. It must not use `S3_BACKUP_CREDENTIALS`: the
server's cluster archives to the root of the same bucket with that key, so
anyone who can read the Secret or exec into `symptoms-<env>` could read and
delete customer Postgres backups. The chart refuses that item and any
destination outside `symptoms/`.

Per environment (`stag`, `can`, `prod`), as a Tigris organization admin, with
the AWS CLI pointed at `iam.storage.dev`:

1. Create the policy `symptoms-<env>-pg-backups` (barman needs to list, read,
   write and expire its own objects):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"],
         "Resource": ["arn:aws:s3:::tuist-<env>-pg-backups/symptoms/*"]
       },
       {
         "Effect": "Allow",
         "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
         "Resource": ["arn:aws:s3:::tuist-<env>-pg-backups"]
       }
     ]
   }
   ```

   `s3:ListBucket` is bucket-level: Tigris conditions do not support
   `s3:prefix`, so the key can list object names elsewhere in the bucket, but
   not read, overwrite or delete them.
2. Create an access key with scope `no_default_allow` (no bucket roles, so it
   cannot create buckets or keys) and attach the policy:
   `aws iam attach-user-policy --policy-arn <arn> --user-name <tid_…>`.
3. Check it from a workstation: a `put`/`get`/`rm` under
   `s3://tuist-<env>-pg-backups/symptoms/` succeeds, and a `get` of any object
   outside `symptoms/` (for example one under `tuist-tuist-pg/`) fails with
   `AccessDenied`.
4. Store the key as `SYMPTOMS_PG_BACKUP` in `tuist-k8s-<env>` with fields
   `access_key_id` and `secret_access_key`.
5. After the first deploy, confirm the cluster's `ContinuousArchiving`
   condition is true and a base backup appears under `symptoms/`.

`infra/helm/tuist-ops` and `infra/helm/mdm` still use `S3_BACKUP_CREDENTIALS`
for their own prefixes; that key is bucket-wide, not prefix-scoped, and they
should move to keys made the same way.

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
