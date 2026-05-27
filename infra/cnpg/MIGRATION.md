# Supabase → CloudNativePG Migration Runbook

End-to-end migration of an environment's Postgres from Supabase to an in-cluster CloudNativePG cluster, using logical replication for the catch-up phase and an atomic cutover during a short read-only window.

Per [the RFC](https://community.tuist.dev/t/moving-postgres-in-cluster/986), three environments migrate in sequence — staging → canary → production — with a soak window between each.

| Env        | Instances | Storage | CPU req / lim | Memory req / lim | Soak before next env |
|------------|-----------|---------|---------------|------------------|----------------------|
| staging    | 2         | 100 GiB | 500m / 1000m  | 2 GiB / 4 GiB    | 72h                  |
| canary     | 3         | 250 GiB | 1000m / 2000m | 4 GiB / 8 GiB    | 48h                  |
| production | 3         | 250 GiB | 2000m / 4000m | 8 GiB / 16 GiB   | n/a (final)          |

## Prerequisites

- The `cloudnative-pg` operator ships as a dependency of the platform
  chart (`infra/helm/platform/Chart.yaml`), so a workload cluster gets
  it automatically on the next `helm upgrade platform` (which the
  `mise run k8s:install-platform` task and `k8s:bootstrap-workload`
  flow both run). No standalone operator install step.
- `kubectl-cnpg` plugin installed locally (`brew install kubectl-cnpg`).
- Per-env 1Password vault populated:
  - `OPS_DATABASE_PASSWORD` (new) — picks any value; CNPG reconciles the role to it.
  - `PROCESSOR_DATABASE_PASSWORD` — already present; reused as-is.
  - `S3_BACKUP_CREDENTIALS` (new) — dedicated Tigris key + secret scoped to the env's `tuist-{env}-pg-backups` bucket.
- Tigris bucket created per env (`tuist-stag-pg-backups`, `tuist-can-pg-backups`, `tuist-prod-pg-backups`). The CNPG `barmanObjectStore` writes a directory tree under the path; no extra prefix needed.

## Per-env migration (repeat for each)

### 1. Provision the CNPG cluster ahead of cutover

The provisioning and cutover phases are split across two chart toggles so the soak window can run with the CNPG cluster live alongside Supabase without touching the live DATABASE_URL:

- `postgresql.cnpg.enabled: true` (already set in `values-managed-common.yaml`) renders the `Cluster` + `ScheduledBackup` + ESO Secrets.
- `postgresql.mode: cnpg` flips `DATABASE_URL` on the server / processor / migration-job pods to the CNPG `<cluster>-app` Secret. Stays at `external` until cutover (step 6).

Provisioning step: the next platform/server deploy with `cnpg.enabled: true` brings up the cluster automatically. To bring it up ahead of the next deploy, apply just the CNPG manifests:

```bash
ENV=staging
kubectl apply -n tuist-$ENV -f <(helm template tuist infra/helm/tuist \
  -f infra/helm/tuist/values-managed-common.yaml \
  -f infra/helm/tuist/values-managed-$ENV.yaml \
  --show-only templates/postgresql-cnpg.yaml \
  --set server.image.tag=$(git rev-parse --short=12 HEAD))
```

Wait for the cluster to reach `phase: Cluster in healthy state`:

```bash
kubectl -n tuist-$ENV cnpg status tuist-tuist-pg --watch
```

### 2. Run the bootstrap SQL

Apply the per-table grants for the managed roles. See [`README.md`](./README.md):

```bash
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -f - \
  < infra/cnpg/tuist-processor-grants.sql

kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -f - \
  < infra/cnpg/tuist-ops-ro-grants.sql
```

### 3. Replicate the schema

Dump the Supabase schema (no data, no oban_* tables) and apply it to the CNPG cluster:

```bash
SUPABASE_DIRECT=$(op read "op://Development/Tuist $(tr '[:lower:]' '[:upper:]' <<<$ENV | sed 's/.*/\u&/') Database (Supabase)/password")
SUPABASE_REF=...   # per env, see infra/supabase/README.md

pg_dump --schema-only --no-owner --no-privileges \
  --exclude-table='oban_*' \
  "postgresql://postgres:$SUPABASE_DIRECT@db.$SUPABASE_REF.supabase.co:5432/postgres?sslmode=require" \
  | kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist
```

### 4. Start logical replication

Create a publication on Supabase covering every table except `oban_jobs` / `oban_peers`. Those are drained pre-cutover instead — duplicating Oban state across two databases creates double-execution risk.

```sql
-- Run on Supabase
CREATE PUBLICATION tuist_migration FOR ALL TABLES;
ALTER PUBLICATION tuist_migration
  DROP TABLE oban_jobs, oban_peers;
```

```bash
# On the CNPG cluster, create a subscription pointed at Supabase.
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist <<SQL
CREATE SUBSCRIPTION tuist_migration
CONNECTION 'postgresql://postgres:$SUPABASE_DIRECT@db.$SUPABASE_REF.supabase.co:5432/postgres?sslmode=require'
PUBLICATION tuist_migration
WITH (copy_data = true, create_slot = true, enabled = true);
SQL
```

Watch lag with `pg_stat_subscription`:

```bash
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -c \
  "SELECT subname, received_lsn, latest_end_lsn, last_msg_send_time, last_msg_receipt_time FROM pg_stat_subscription;"
```

Wait until `received_lsn = latest_end_lsn` and the lag stays at zero for several minutes.

### 5. Soak

Let the replica run zero-lag for the soak window above (72h staging, 48h canary, 72h production). During the soak, schema migrations land on Supabase as before — logical replication relays the row changes. DDL changes do **not** replicate; if a migration adds a new table, replay the DDL against the CNPG cluster manually before the next deploy.

### 6. Cutover

Maintenance window required. The flip itself is ~30 seconds — Phoenix briefly returns 503s while the chart switches DATABASE_URL.

```bash
# 6a. Set the deployment read-only (post a banner / scale the server to 0
# for harder reads-blocked behavior). For the canonical RFC path, the
# /ops/db page exposes a "Maintenance mode" toggle.

# 6b. Drain Oban jobs. Pause the queues, wait for in-flight jobs to
# settle, then export and re-import to oban_jobs on CNPG.
kubectl -n tuist-$ENV exec deploy/tuist-tuist-server -- \
  /app/bin/tuist eval 'Oban.pause_all_queues(Oban)'

# Wait for `executing` count to reach 0 in /ops/dashboard's Oban tab.

# 6c. Take a final pg_dump of oban_jobs / oban_peers and import.
pg_dump --data-only --table=oban_jobs --table=oban_peers \
  "postgresql://postgres:$SUPABASE_DIRECT@db.$SUPABASE_REF.supabase.co:5432/postgres?sslmode=require" \
  | kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist

# 6d. Drop the subscription (it will refuse new writes from Supabase but
# the migration source is paused anyway).
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist \
  -c "ALTER SUBSCRIPTION tuist_migration DISABLE;"

# 6e. Land the cutover PR that flips `postgresql.mode` to `cnpg` in
# the env overlay (`values-managed-$ENV.yaml`). The chart's
# server-deployment / processor-external-secrets / server-migration-job
# templates then inject DATABASE_URL from the CNPG `<cluster>-app`
# Secret and from the `tuist_processor` ESO secret. No change to
# priv/secrets/<env>.yml.enc is needed — the chart env var takes
# precedence over the encrypted-bundle DATABASE_URL.
gh workflow run server-deployment.yml -f environment=$ENV

# 6f. Resume Oban queues.
kubectl -n tuist-$ENV exec deploy/tuist-tuist-server -- \
  /app/bin/tuist eval 'Oban.resume_all_queues(Oban)'
```

### 7. Reverse replication for rollback (14 days)

For the next 14 days, replicate CNPG → Supabase so a rollback is a flip of DATABASE_URL back to Supabase, not a multi-hour data-export. Same `CREATE PUBLICATION` / `CREATE SUBSCRIPTION` pattern in the opposite direction.

After 14 days of clean operation, drop the reverse subscription and decommission the Supabase project for that env.

## Per-environment soak gates

Before promoting to the next env:
- `pg_stat_subscription.lag` stayed at zero for the full soak window.
- `kubectl cnpg status` reports `Cluster in healthy state` and `Healthy primary`.
- A restore-validation drill ran successfully against a fresh cluster created from the latest base backup.
- Phoenix `/ready` returns 200 from every server pod with the new DATABASE_URL active.

## Out of scope

- ClickHouse migration (planned as follow-on work).
- Multi-region failover capabilities.
- Self-hoster single-pod deployments (unchanged — `postgresql.mode: embedded` remains the supported shape).
- Schema migration mechanics (existing Ecto flow continues).
