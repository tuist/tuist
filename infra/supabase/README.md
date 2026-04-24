# Supabase

One-shot SQL files for bootstrapping Postgres state that app migrations can't own, because they run as the `postgres` superuser and the Supabase app role doesn't have `CREATEROLE`.

## Files

- [`tuist-processor-role.sql`](./tuist-processor-role.sql) — least-privilege role scoped to the Oban job table and the build-result write surface. Dormant until the processor is switched to an Oban Pro queue model; see PR [#10428](https://github.com/tuist/tuist/pull/10428) for the tradeoff analysis.

## When to run

- **New Supabase project** (e.g., spinning up a fourth env): run each file once, before the first app deploy, against the env's Supabase project.
- **Password rotation**: follow the rotation snippet at the top of each SQL file — `ALTER ROLE ... PASSWORD` only, no schema change.
- **Grant surface change** (a new table in the worker's write path, say): edit the SQL file, re-run it against every env, commit the change. The `REVOKE ALL` + re-`GRANT` pattern makes each run idempotent.

## How to run

Two paths:

1. **Supabase Dashboard → SQL Editor**, paste the file contents, set the `pw` variable at the top, click Run. Fine for one-off bootstrap.
2. **Direct psql** (reproducible, scriptable):

   ```bash
   # Direct URL lives in Supabase Dashboard → Settings → Database → Connection string → URI.
   # Use port 5432, not the pooler (6543) — role changes need a session.
   export DIRECT_URL="$(op read 'op://tuist-k8s-<env>/SUPABASE_DIRECT_URL/password')"
   export PW="$(op read 'op://tuist-k8s-<env>/PROCESSOR_DATABASE_URL/password')"

   psql "$DIRECT_URL" -v pw="$PW" \
     -f infra/supabase/tuist-processor-role.sql
   ```

The file ends with a `SELECT … information_schema.role_table_grants …` sanity query, so a clean run prints the exact set of tables + privileges the role holds.

## Why not an Ecto migration

Three reasons, worst to best:

1. **Permissions.** `CREATE ROLE` needs `CREATEROLE` on the connecting role. Supabase's app role doesn't have it. Only the `postgres` superuser can create roles, and the app never connects as `postgres` in prod.
2. **Ownership.** Role state is infra, not app schema. Binding it to migrations means a fresh-env bring-up fails until someone manually bootstraps the role — circular.
3. **Future flexibility.** If we ever move Postgres in-cluster (see [#10368](https://github.com/tuist/tuist/pull/10368) § "Why not bare metal?"), the declarative path is the Postgres operator's Cluster CR, not another Ecto migration. Keeping role provisioning SQL here makes that future collapse trivial.
