-- Least-privilege Postgres role for the in-cluster processor.
--
-- Currently dormant: the processor in this chart uses HTTP webhooks + the
-- /stats endpoint for least-busy dispatch, so it needs no DB access at all.
-- This role only comes into play if we ever switch the processor to an
-- Oban Pro queue model where it pulls jobs from Postgres directly (see the
-- PR #10428 thread for the tradeoff analysis).
--
-- Why a file rather than an Ecto migration:
--   1. Supabase only lets the `postgres` superuser run `CREATE ROLE`; the app
--      role Ecto connects as doesn't have `CREATEROLE`.
--   2. Role provisioning is infra state, not app schema. Tying it to Ecto
--      migrations means a fresh-env bring-up fails until someone creates the
--      role first — the exact problem this file is structured to avoid.
--   3. If/when we move Postgres in-cluster, this file gets collapsed into the
--      Postgres operator's Cluster CR (declarative role management).
--
-- Usage (one-shot per Supabase project):
--
--   export DIRECT_URL="$(op read 'op://tuist-k8s-<env>/SUPABASE_DIRECT_URL/password')"
--   export PW="$(op read 'op://tuist-k8s-<env>/PROCESSOR_DATABASE_URL/password')"
--   psql "$DIRECT_URL" -v pw="$PW" \
--     -f infra/supabase/tuist-processor-role.sql
--
-- Rotation (password only, no schema change):
--
--   export PW="$(openssl rand -base64 32 | tr -d '/+=')"
--   op item edit "op://tuist-k8s-<env>/PROCESSOR_DATABASE_URL" password="$PW"
--   psql "$DIRECT_URL" -c "ALTER ROLE tuist_processor WITH PASSWORD '$PW';"
--
-- Run this as the `postgres` superuser (Supabase Dashboard → SQL Editor, or
-- psql against the direct connection string from Settings → Database).

BEGIN;

-- Create the role (idempotent — DO block so re-running doesn't error).
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tuist_processor') THEN
    EXECUTE format('CREATE ROLE tuist_processor LOGIN PASSWORD %L', :'pw');
  ELSE
    EXECUTE format('ALTER ROLE tuist_processor WITH PASSWORD %L', :'pw');
  END IF;
END
$$;

-- Connect + schema access
GRANT CONNECT ON DATABASE postgres TO tuist_processor;
GRANT USAGE ON SCHEMA public TO tuist_processor;

-- Oban coordination. DELETE is needed for completed-job pruning.
GRANT SELECT, INSERT, UPDATE, DELETE ON oban_jobs, oban_peers TO tuist_processor;
GRANT USAGE, SELECT ON SEQUENCE oban_jobs_id_seq TO tuist_processor;

-- Build-run writes. Narrow to the tables ProcessBuildWorker touches via
-- `Tuist.Builds.create_build/1`. Update the list if the worker's write
-- surface grows — the REVOKE ALL below stops silent fanout, but a grep
-- for `Tuist.Repo.insert` + `Tuist.Repo.update` under lib/tuist/builds/
-- is the source of truth.
GRANT SELECT, INSERT, UPDATE ON
  builds, build_targets, build_issues, build_files,
  cacheable_tasks, cas_outputs, build_machine_metrics
TO tuist_processor;

-- Read-only lookups the worker performs (accounts.get_account_by_id, etc.).
-- Keep tight: `users`, `user_tokens`, `sessions`, billing — not listed here
-- on purpose.
GRANT SELECT ON projects, accounts TO tuist_processor;

-- Explicit deny on everything else. Future migrations that add tables won't
-- grant tuist_processor anything unless we update this file.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM tuist_processor;
GRANT SELECT, INSERT, UPDATE, DELETE ON oban_jobs, oban_peers TO tuist_processor;
GRANT SELECT, INSERT, UPDATE ON
  builds, build_targets, build_issues, build_files,
  cacheable_tasks, cas_outputs, build_machine_metrics
TO tuist_processor;
GRANT SELECT ON projects, accounts TO tuist_processor;

COMMIT;

-- Post-apply sanity check (not wrapped in the transaction so it always runs):
SELECT
  grantee, table_name,
  string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'tuist_processor'
GROUP BY grantee, table_name
ORDER BY table_name;
