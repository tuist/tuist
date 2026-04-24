# Supabase

One-shot SQL files for bootstrapping Postgres state that app migrations can't own, because they run as the `postgres` superuser and the Supabase app role doesn't have `CREATEROLE`.

## Files

- [`tuist-processor-role.sql`](./tuist-processor-role.sql) — least-privilege Postgres role the processor pods connect as. Required before the first deploy that sets `processor.enabled: true` in the Helm chart, otherwise ESO syncs an empty `DATABASE_URL` and processor pods crashloop.

## When to run

- **Before enabling `processor.enabled` for the first time** in a given env. Managed deployments: run against all three Supabase projects (staging / canary / production) before merging a chart change that enables the processor.
- **Password rotation**: follow the rotation snippet at the top of each SQL file — `ALTER ROLE ... PASSWORD` only, no schema change.
- **Grant surface change** (a new table the worker needs to read, say): edit the SQL file, re-run against every env, commit the change. The `REVOKE ALL` + re-`GRANT` pattern makes each run idempotent.

## How to run

Two paths:

1. **Supabase Dashboard → SQL Editor**, paste the file contents, replace `:'pw'` with a quoted password literal, click Run. Fine for one-off bootstrap.
2. **Direct psql** (reproducible, scriptable — recommended):

   ```bash
   # Direct URL lives in Supabase Dashboard → Settings → Database → Connection string → URI.
   # Use port 5432, not the pooler (6543) — role changes need a session.
   export DIRECT_URL="$(op read 'op://tuist-k8s-<env>/SUPABASE_DIRECT_URL/password')"
   export PW="$(op read 'op://tuist-k8s-<env>/PROCESSOR_DATABASE_URL/password')"

   psql "$DIRECT_URL" -v pw="$PW" \
     -f infra/supabase/tuist-processor-role.sql
   ```

The file ends with a `SELECT … information_schema.role_table_grants …` sanity query, so a clean run prints the exact set of tables + privileges the role holds.

## Populating `PROCESSOR_DATABASE_URL` in 1Password

Construct the URL from the Supabase pooler (port 6543, transaction mode) plus the role's password:

```
postgres://tuist_processor:<PW>@<pooler-host>:6543/postgres?sslmode=require&channel_binding=require
```

Put that full URL in the `password` field of a `PROCESSOR_DATABASE_URL` item in the env's `tuist-k8s-<env>` vault. ESO's `ExternalSecret` in the chart (see [`infra/helm/tuist/templates/processor-external-secrets.yaml`](../helm/tuist/templates/processor-external-secrets.yaml)) picks it up on the next refresh and feeds it to the processor pods as the `DATABASE_URL` env var.

## Why not an Ecto migration

Three reasons, worst to best:

1. **Permissions.** `CREATE ROLE` needs `CREATEROLE` on the connecting role. Supabase's app role doesn't have it. Only the `postgres` superuser can create roles, and the app never connects as `postgres` in prod.
2. **Ownership.** Role state is infra, not app schema. Binding it to migrations means a fresh-env bring-up fails until someone manually bootstraps the role — circular.
3. **Future flexibility.** If we ever move Postgres in-cluster (see [PR #10368](https://github.com/tuist/tuist/pull/10368) § "Why not bare metal?"), the declarative path is the Postgres operator's Cluster CR, not another Ecto migration. Keeping role provisioning SQL here makes that future collapse trivial.
