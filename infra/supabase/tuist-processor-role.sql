-- Least-privilege Postgres role for the Oban-queue processor.
--
-- The processor pod is the `ProcessBuildWorker` consumer: it pulls jobs from
-- the oban_jobs table, reads `accounts` and `projects` to resolve the build's
-- owner, downloads the archive from S3, and writes parsed results to the
-- ClickHouse builds tables via Tuist.IngestRepo. ClickHouse has its own auth
-- plane and is scoped independently (out of this file's scope).
--
-- Why a file rather than an Ecto migration:
--   1. Supabase only lets the `postgres` superuser run `CREATE ROLE`; the app
--      role Ecto connects as doesn't have `CREATEROLE`.
--   2. Role provisioning is infra state, not app schema. Tying it to Ecto
--      migrations means a fresh-env bring-up fails until someone creates the
--      role first — the exact problem this file is structured to avoid.
--   3. If/when we move Postgres in-cluster, this file gets collapsed into
--      the Postgres operator's Cluster CR (declarative role management).
--
-- Usage (one-shot per Supabase project, before the first deploy that enables
-- `processor.enabled: true` in the Helm chart):
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

-- Create the role (idempotent on re-run).
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'tuist_processor') THEN
    EXECUTE format('CREATE ROLE tuist_processor LOGIN PASSWORD %L', :'pw');
  ELSE
    EXECUTE format('ALTER ROLE tuist_processor WITH PASSWORD %L', :'pw');
  END IF;
END
$$;

GRANT CONNECT ON DATABASE postgres TO tuist_processor;
GRANT USAGE ON SCHEMA public TO tuist_processor;

-- Oban coordination. DELETE is needed for Oban.Plugins.Pruner.
GRANT SELECT, INSERT, UPDATE, DELETE ON oban_jobs, oban_peers TO tuist_processor;
GRANT USAGE, SELECT ON SEQUENCE oban_jobs_id_seq TO tuist_processor;

-- Read-only lookups the worker performs. accounts.get_account_by_id/1
-- resolves the account for S3 scoping; Project |> Repo.get/2 reads the
-- project to decide whether to broadcast PubSub. Neither row is written to
-- by the worker — hence no INSERT/UPDATE.
GRANT SELECT ON accounts, projects TO tuist_processor;

-- Everything else stays off-limits. Re-run this file after adding a new
-- table-read to the worker; the REVOKE + re-GRANT pattern makes the
-- intersection explicit and idempotent.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM tuist_processor;
GRANT SELECT, INSERT, UPDATE, DELETE ON oban_jobs, oban_peers TO tuist_processor;
GRANT SELECT ON accounts, projects TO tuist_processor;

COMMIT;

-- Sanity check (outside the transaction, always runs):
SELECT
  grantee, table_name,
  string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'tuist_processor'
GROUP BY grantee, table_name
ORDER BY table_name;
