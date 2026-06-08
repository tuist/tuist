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
- `kubectl-cnpg` plugin (`brew install kubectl-cnpg`) and `psql` installed locally. The publication step connects to Supabase directly.
- Per-env 1Password vault populated:
  - `OPS_DATABASE_PASSWORD` (new) — picks any value; CNPG reconciles the role to it.
  - `PROCESSOR_DATABASE_PASSWORD` — already present; reused as-is.
  - `S3_BACKUP_CREDENTIALS` (new) — dedicated Tigris key + secret scoped to the env's `tuist-{env}-pg-backups` bucket.
- The Supabase superuser password is in 1Password as `Tuist <Env> Database (Supabase)` in the `Development` vault. `op read` mishandles the parentheses in the title, so read it with `op item get`:
  ```bash
  SUPABASE_PW=$(op item get "Tuist Staging Database (Supabase)" --vault Development --fields label=password --reveal)
  SUPABASE_REF=inzgspjesrhqhleomvkb   # staging; canary / production refs live in each values-managed-<env>.yaml under processor.database.host
  ```
- Tigris bucket created per env (`tuist-stag-pg-backups`, `tuist-can-pg-backups`, `tuist-prod-pg-backups`). The CNPG `barmanObjectStore` writes a directory tree under the path; no extra prefix needed.

## Connection budget

The CNPG cluster's `max_connections` is set explicitly via `postgresql.cnpg.parameters.max_connections` (the operator default is 100). Unlike Supabase, a CNPG cluster has no managed pooler in front by default, so the app's connections land on Postgres directly and the cluster must be sized for the aggregate:

```
max_connections  ≳  (web replicas × TUIST_DATABASE_POOL_SIZE)
                   + processor pool
                   + migration job (pool 1, transient)
                   + pooler backend pool (if the Pooler is enabled)
                   + ~15 for replication walsenders, monitoring, and
                     superuser_reserved_connections (3)
                   + headroom for a deploy surge (maxSurge adds a replica)
```

The web tier is the dominant term, and it scales with replica count:

| Env        | Web replicas (max) | Pool | Web peak | `max_connections` |
|------------|--------------------|------|----------|-------------------|
| staging    | 1                  | 15   | 15       | 100 (default)     |
| canary     | 1                  | 30   | 30       | 100 (default)     |
| production | 5 (autoscaled)     | 15   | 75       | **200**           |

**Do not raise the per-replica pool on a multi-replica env to match canary's 30.** Canary can afford a 30-connection pool because it is a single replica (30 < 100). On production, 5 replicas × 30 = 150 would blow past `max_connections` and surface as Postgres-side `remaining connection slots` / `too many clients` refusals — a different and worse failure than app-side pool pressure. Scale the web tier's connection pressure with replicas, not with a fat per-replica pool, and keep `max_connections` ahead of the peak.

Raising `max_connections` costs roughly 5–10 MiB of shared memory per connection, so keep it proportionate to the instance's memory limit (200 connections ≈ ~2 GiB, comfortable inside production's 16 GiB).

Optionally, a CNPG `Pooler` (PgBouncer) can front the cluster for the **processor** only, in transaction mode — matching the processor's Supabase Supavisor `:6543` path so its `prepare: :unnamed` shape is unchanged across cutover. The web tier connects straight to `-rw` instead. Note this differs from Supabase, where the web tier rides Supavisor in *session* mode (`:5432`); we skip that hop because `-rw` is already a native session endpoint with failover and a session pooler would not change the budget. See [`README.md`](./README.md) → "Connection pooler (PgBouncer)" for the full rationale and the activation sequence.

## Per-env migration (repeat for each)

### 1. Provision the CNPG cluster ahead of cutover

The provisioning and cutover phases are split across two chart toggles so the soak window can run with the CNPG cluster live alongside Supabase without touching the live DATABASE_URL:

- `postgresql.cnpg.enabled: true` (already set in `values-managed-common.yaml`) renders the `Cluster` + `ScheduledBackup` + ESO Secrets.
- `postgresql.mode: cnpg` flips `DATABASE_URL` on the server / processor / migration-job pods to the CNPG `<cluster>-app` Secret. Stays at `external` until cutover (step 6).

Provisioning step: the next platform/server deploy with `cnpg.enabled: true` brings up the cluster automatically. To bring it up ahead of the next deploy, apply just the CNPG manifests:

```bash
ENV=staging
SHA=$(git rev-parse --short=12 HEAD)
# `--namespace` is required: the template's backups-reader RoleBinding
# subject is rendered with `.Release.Namespace`, so without it the
# binding would point at `tuist-server` in `default` — `kubectl apply
# -n` only places the resource, it doesn't rewrite fields inside it.
# `--show-only` still requires every chart-required image tag, even for
# templates that aren't rendered, so pass kuraController.image.tag
# alongside server.image.tag.
kubectl apply -n tuist-$ENV -f <(helm template tuist infra/helm/tuist \
  --namespace tuist-$ENV \
  -f infra/helm/tuist/values-managed-common.yaml \
  -f infra/helm/tuist/values-managed-$ENV.yaml \
  --show-only templates/postgresql-cnpg.yaml \
  --set server.image.tag=$SHA \
  --set kuraController.image.tag=$SHA)
```

Wait for the cluster to reach `phase: Cluster in healthy state`:

```bash
kubectl -n tuist-$ENV cnpg status tuist-tuist-pg --watch
```

### 2. Build the schema by running the migrations

Do **not** `pg_dump` the Supabase schema onto CNPG. The Supabase `postgres` database carries state the in-cluster cluster must not inherit: Supabase system schemas (`auth`, `storage`, `realtime`, `vault`, ...), the `timescaledb` extension plus a legacy `build_runs` hypertable, `extensions`-schema-qualified column defaults, and Rails-era leftovers (`que_*`, `ar_internal_metadata`). A dump drags all of it along and fails to apply on the vanilla CNPG image.

Instead build the canonical schema the same way cutover will: run the Ecto migrations against the cluster as the `tuist_app` owner. That creates `citext` + `uuid-ossp` in `public`, every app table owned by `tuist_app`, and nothing Supabase-specific.

Run it as a one-off Job (in-cluster, so it reaches the `-rw` Service natively and mounts the same secrets the real migration-job uses). Give the Job **neutral labels**: the workload clusters reap Jobs carrying `app.kubernetes.io/name: tuist` that are not tracked in a Helm release, so a Job rendered straight from the chart template gets deleted before it runs.

```bash
ENV=staging
# `TUIST_DEPLOY_ENV` is the deploy-env *alias* (`stag` / `can` / `prod`)
# the release looks up under `priv/secrets/`, NOT the namespace suffix.
# Map it before launching the Job — passing `staging` here makes the
# release try to decrypt `priv/secrets/staging.yml.enc`, which doesn't
# exist, and the migration job fails to start.
case "$ENV" in
  staging)    DEPLOY_ENV=stag ;;
  canary)     DEPLOY_ENV=can  ;;
  production) DEPLOY_ENV=prod ;;
esac
IMG=$(kubectl -n tuist-$ENV get deploy tuist-tuist-server -o jsonpath='{.spec.template.spec.containers[0].image}')
kubectl create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: cnpg-schema-migrate
  namespace: tuist-$ENV
  labels: { purpose: cnpg-schema-soak }
spec:
  backoffLimit: 1
  template:
    metadata:
      labels: { purpose: cnpg-schema-soak }
    spec:
      serviceAccountName: tuist-server
      restartPolicy: Never
      containers:
        - name: migrate
          image: "$IMG"
          command: ["/app/bin/tuist", "eval", "Tuist.Release.migrate"]
          env:
            - { name: DATABASE_URL, valueFrom: { secretKeyRef: { name: tuist-tuist-pg-app, key: uri } } }
            - { name: TUIST_USE_SSL_FOR_DATABASE, value: "0" }
            - { name: TUIST_DEPLOY_ENV, value: "$DEPLOY_ENV" }
            - { name: TUIST_HOSTED, value: "1" }
            - { name: MASTER_KEY, valueFrom: { secretKeyRef: { name: tuist-tuist-server-external-secrets, key: server-master-key } } }
YAML
kubectl -n tuist-$ENV wait --for=condition=complete job/cnpg-schema-migrate --timeout=10m
```

Confirm `citext` + `uuid-ossp` exist and the app tables are owned by `tuist_app`. If the image already carries the `drop_legacy_build_runs_hypertable` migration, `build_runs` is gone; otherwise it lands as an empty plain table (harmless, excluded from replication below).

### 3. Apply the per-table grants

Now that the tables exist, apply the per-table grants for the managed roles (the grant SQL references `oban_jobs` / `accounts` / `projects`, so it must run after step 2). See [`README.md`](./README.md):

```bash
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -f - \
  < infra/cnpg/tuist-processor-grants.sql

kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -f - \
  < infra/cnpg/tuist-ops-ro-grants.sql
```

### 4. Start logical replication

`FOR ALL TABLES` does not work here. The publication must contain exactly the tables present on **both** Supabase and CNPG, because the two schemas drift: Supabase keeps tables dropped from the current migrations (e.g. `runner_assignments`), and CNPG creates tables already removed from Supabase out-of-band (e.g. `artifacts`, `bundles`). Publishing a table the subscriber lacks aborts `CREATE SUBSCRIPTION`. Also always exclude `oban_jobs` / `oban_peers` (drained at cutover; double-execution risk), `build_runs` (dead), `schema_migrations` (each database owns its own), and unlogged tables (`que_lockers`: logical replication cannot publish unlogged relations).

Set `SUPA` to the direct connection (read the password as shown above):

```bash
SUPA="postgresql://postgres:$SUPABASE_PW@db.$SUPABASE_REF.supabase.co:5432/postgres?sslmode=require"
```

**4a. On Supabase** — give PK-less tables a replica identity, or their UPDATE/DELETE will not replicate:

```sql
ALTER TABLE public.users_roles REPLICA IDENTITY FULL;
ALTER TABLE public.que_scheduler_audit_enqueued REPLICA IDENTITY FULL;
```

**4b. Compute the intersection and create the publication.** List the candidate tables on both sides (permanent + public, minus the always-excluded set; `relpersistence='p'` drops unlogged tables automatically) and publish only the overlap. Review the two diff lists before proceeding:

```bash
FILTER="c.relkind='r' AND c.relpersistence='p' AND c.relname NOT IN ('oban_jobs','oban_peers','build_runs','schema_migrations')"
Q="SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND $FILTER ORDER BY 1;"
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -tAc "$Q" | grep -E '^[a-z]' | sort -u > /tmp/cnpg.txt
psql "$SUPA" -tAc "$Q" | grep -E '^[a-z]' | sort -u > /tmp/supa.txt
comm -13 /tmp/cnpg.txt /tmp/supa.txt   # Supabase-only (will NOT be migrated; confirm each is dead)
comm -23 /tmp/cnpg.txt /tmp/supa.txt   # CNPG-only (no source, stays empty; confirm acceptable)
comm -12 /tmp/cnpg.txt /tmp/supa.txt > /tmp/pub.txt
TBLS=$(sed 's/^/public./' /tmp/pub.txt | paste -sd', ' -)
psql "$SUPA" -c "DROP PUBLICATION IF EXISTS tuist_migration; CREATE PUBLICATION tuist_migration FOR TABLE $TBLS;"
```

**4c. On CNPG** — create the subscription:

```bash
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist <<SQL
CREATE SUBSCRIPTION tuist_migration CONNECTION '$SUPA'
PUBLICATION tuist_migration WITH (copy_data = true, create_slot = true, enabled = true);
SQL
```

If a previous attempt failed, drop the orphaned slot on Supabase first: `psql "$SUPA" -c "SELECT pg_drop_replication_slot('tuist_migration');"`.

**4d. Clear seed-data conflicts.** Several Ecto migrations seed default rows (e.g. `oauth_scopes`, `cache_endpoints`). Those rows collide with the initial COPY, wedging the per-table sync worker in a crash loop (`duplicate key value violates unique constraint`; the table stays in `srsubstate='d'`). Find the wedged tables and empty them; the sync worker retries automatically into the now-empty table and pulls the authoritative Supabase rows:

```bash
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -tAc \
  "SELECT srrelid::regclass FROM pg_subscription_rel WHERE srsubstate <> 'r';"
# For each: DELETE (FK-safe when referencing tables are empty) or TRUNCATE ... CASCADE.
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -c "DELETE FROM oauth_scopes; DELETE FROM cache_endpoints;"
```

**4e. Wait for steady state** — every table reports `srsubstate='r'` and lag holds at zero:

```bash
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -tAc \
  "SELECT count(*) FILTER (WHERE srsubstate='r') || '/' || count(*) FROM pg_subscription_rel;"
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist -tAc \
  "SELECT pg_size_pretty(pg_wal_lsn_diff(latest_end_lsn, received_lsn)) FROM pg_stat_subscription WHERE subname='tuist_migration';"
```

### 5. Soak

Let the replica run zero-lag for the soak window above (72h staging, 48h canary, 72h production). During the soak:

- **DDL does not replicate.** A migration landing on Supabase relays its row changes but not the schema change. Re-run the migrate Job from step 2 (or replay the DDL by hand) against CNPG before the next deploy, and `ALTER PUBLICATION tuist_migration ADD TABLE public.<new_table>` for any table the migration added (then `ALTER SUBSCRIPTION tuist_migration REFRESH PUBLICATION` on CNPG).
- **The replication slot pins WAL on Supabase** until cutover. If the soak runs long, watch Supabase disk usage; a stalled subscriber lets WAL accumulate.

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
pg_dump --data-only --table=oban_jobs --table=oban_peers "$SUPA" \
  | kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist

# 6d. Drop the subscription (it will refuse new writes from Supabase but
# the migration source is paused anyway).
kubectl cnpg psql -n tuist-$ENV tuist-tuist-pg -- -d tuist \
  -c "ALTER SUBSCRIPTION tuist_migration DISABLE;"

# 6e. Land the cutover PR that flips `postgresql.mode` to `cnpg` in
# the env overlay (`values-managed-$ENV.yaml`). In the SAME change, set
# `postgresql.cnpg.pooler.enabled: true` so the processor moves straight
# from Supabase's transaction pooler (Supavisor :6543) onto the CNPG
# transaction pooler (`-pooler-rw`), keeping its `prepare: :unnamed`
# shape. Enabling the pooler only *after* cutover would briefly land the
# processor on `-rw` directly (session / `prepare: :named`) and then flip
# its shape a second time — so flip both together. (staging and canary
# already run with the pooler on, so for them only `mode` changes here;
# production is the env that flips both.) The chart's server-deployment /
# processor-external-secrets / server-migration-job templates then inject
# DATABASE_URL from the CNPG `<cluster>-app` Secret and from the
# `tuist_processor` ESO secret. No change to priv/secrets/<env>.yml.enc
# is needed — the chart env var takes precedence over the
# encrypted-bundle DATABASE_URL.
gh workflow run server-deployment.yml -f environment=$ENV

# 6f. Resume Oban queues.
kubectl -n tuist-$ENV exec deploy/tuist-tuist-server -- \
  /app/bin/tuist eval 'Oban.resume_all_queues(Oban)'
```

### 7. Rollback strategy (14 days, fix-forward by default)

After cutover the rollback path is **fix-forward on CNPG**, not flip-back-to-Supabase. The Supabase project stays live but unused as a frozen pre-cutover snapshot for 14 days, then is decommissioned.

We chose this over continuous CNPG → Supabase reverse replication after weighing the trade-offs. Reverse replication would buy ~5-minute rollback at the cost of: a public-facing Hetzner LB exposing CNPG (extra attack surface even with source-IP ACLs), a second logical replication slot with the same `statement_timeout` / `max_slot_wal_keep_size` / slot-invalidation failure modes we hit during the forward COPY (now failing silently and discovered on the day rollback is needed), a `tuist_replicator` role on CNPG with REPLICATION privilege, and chart additions for `pg_hba` injection + managed role declaration. That's a lot of net-new operational surface to protect against scenarios where rolling back to Supabase doesn't actually help — Supabase wouldn't have the post-cutover writes anyway, so any rollback past hour-1 would require manual data reconciliation either way, and every realistic CNPG failure mode (data corruption, performance regression, ops gap) is recoverable on CNPG via the existing safety nets.

#### Safety nets already in place

- Base backups to Tigris (`tuist-<env>-pg-backups`), daily via `ScheduledBackup`.
- Continuous WAL archive to the same bucket → point-in-time recovery to any second within the retention window.
- Restore-validation drill has been proven end-to-end against the staging cluster.
- The Supabase project for the env stays running, untouched, as a frozen snapshot for 14 days.

#### Emergency rollback in the first 24h

If a problem surfaces inside the first day and we need to genuinely flip back to Supabase:

1. Pause writes (Maintenance mode toggle on `/ops/db`, or scale the server to 0).
2. Identify the small write delta on CNPG since cutover (timestamp-bounded `pg_dump --data-only --table=...` for the high-write tables, or a row-count diff against Supabase).
3. Apply the delta to Supabase as the superuser (`op://Development/Tuist <Env> Database (Supabase)`).
4. Open a one-line revert PR flipping `postgresql.mode` and `postgresql.cnpg.pooler.enabled` back to `external` / `false` for the env.
5. Merge + deploy. Server switches back to Supabase.

Wall-time depends on the delta size, but a same-day rollback is on the order of one operator-hour, not the multi-hour COPY a fresh forward migration would take.

#### Beyond the first 24h

Fix-forward on CNPG. Drift between CNPG and Supabase grows monotonically and we'd be reconciling manually anyway — at that point a "rollback" is really a from-scratch migration in the reverse direction, the same operation we just did forward.

#### Day-14 decommission

Drop the Supabase project for the env and remove any remaining references (1Password items, processor `database.host` overlay value, pg_dump scripts pointing at it).

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
