-- Per-table privileges for the `tuist_processor` role.
--
-- CNPG creates the role declaratively from
-- `managed.roles[name=tuist_processor]` in the chart-rendered
-- `Cluster` CR; this file adds the per-table GRANTs that the worker
-- needs on top of an empty role. Re-runnable: the GRANT statements are
-- idempotent on a fixed table set.
--
-- Primary applier: `Tuist.Release.do_grant_processor_role/2` re-runs the
-- same grant set as the schema owner on every migrate (gated on
-- TUIST_DATABASE_PROCESSOR_ROLE), so managed CNPG envs stay in sync with
-- schema changes automatically. This file is now the bootstrap/restore
-- fallback for the window before the first migrate runs. Keep the two in
-- sync: a table added to `do_grant_processor_role` belongs here too.
--
-- The grant set tracks the Postgres surface the processor role touches: the
-- build worker (`server/lib/tuist/builds/workers/process_build_worker.ex`)
-- and the xcresult/test ingestion path (`Tuist.Tests.create_test/1` ->
-- `create_test_modules`, which reads `automation_alerts` when scheduling
-- scoped flaky-test evaluations and `webhook_endpoints` when a run
-- introduces a first-run test case). Adding a new Postgres read or write
-- in those paths means adding the corresponding GRANT here and in
-- `do_grant_processor_role` in the same change.
--
-- See infra/cnpg/README.md for how to run this file against a fresh
-- cluster (or after a backup restore).

\if :{?tuist_schema}
\else
\set tuist_schema public
\endif

BEGIN;

-- Re-assert the intersection explicitly. New tables added by future
-- migrations stay off-limits until grants are re-issued here; the
-- REVOKE + re-GRANT pattern keeps the intent obvious.
REVOKE ALL ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_processor;

GRANT CONNECT ON DATABASE tuist TO tuist_processor;
GRANT USAGE ON SCHEMA :"tuist_schema" TO tuist_processor;

-- Oban coordination. DELETE is needed for Oban.Plugins.Pruner.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE :"tuist_schema".oban_jobs, :"tuist_schema".oban_peers TO tuist_processor;
GRANT USAGE, SELECT ON SEQUENCE :"tuist_schema".oban_jobs_id_seq TO tuist_processor;

-- Read-only lookups the workers perform. These rows are not written by the
-- processors, hence no INSERT/UPDATE.
GRANT SELECT ON TABLE :"tuist_schema".accounts, :"tuist_schema".projects, :"tuist_schema".automation_alerts, :"tuist_schema".webhook_endpoints TO tuist_processor;

COMMIT;

-- Sanity check.
SELECT
  grantee, table_name,
  string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'tuist_processor' AND table_schema = :'tuist_schema'
GROUP BY grantee, table_name
ORDER BY table_name;
