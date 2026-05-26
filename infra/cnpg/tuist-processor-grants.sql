-- Per-table privileges for the `tuist_processor` role.
--
-- CNPG creates the role declaratively from
-- `managed.roles[name=tuist_processor]` in the chart-rendered
-- `Cluster` CR; this file adds the per-table GRANTs that the worker
-- needs on top of an empty role. Re-runnable: the GRANT statements are
-- idempotent on a fixed table set.
--
-- See infra/cnpg/README.md for how to run this file against a fresh
-- cluster (or after a backup restore).

BEGIN;

GRANT CONNECT ON DATABASE tuist TO tuist_processor;
GRANT USAGE ON SCHEMA public TO tuist_processor;

-- Oban coordination. DELETE is needed for Oban.Plugins.Pruner.
GRANT SELECT, INSERT, UPDATE, DELETE ON oban_jobs, oban_peers TO tuist_processor;
GRANT USAGE, SELECT ON SEQUENCE oban_jobs_id_seq TO tuist_processor;

-- Read-only lookups the worker performs. accounts.get_account_by_id/1
-- resolves the account for S3 scoping; Project |> Repo.get/2 reads the
-- project to decide whether to broadcast PubSub. Neither row is written
-- to by the worker — hence no INSERT/UPDATE.
GRANT SELECT ON accounts, projects TO tuist_processor;

-- Re-assert the intersection explicitly. New tables added by future
-- migrations stay off-limits until grants are re-issued here; the
-- REVOKE + re-GRANT pattern keeps the intent obvious.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM tuist_processor;
GRANT SELECT, INSERT, UPDATE, DELETE ON oban_jobs, oban_peers TO tuist_processor;
GRANT SELECT ON accounts, projects TO tuist_processor;

COMMIT;

-- Sanity check.
SELECT
  grantee, table_name,
  string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'tuist_processor'
GROUP BY grantee, table_name
ORDER BY table_name;
