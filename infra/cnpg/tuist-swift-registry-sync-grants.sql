-- Per-table privileges for the `tuist_swift_registry_sync` role.
--
-- CNPG creates the role declaratively from
-- `managed.roles[name=tuist_swift_registry_sync]` in the chart-rendered
-- `Cluster` CR; this file adds the per-table GRANTs that the worker
-- needs on top of an empty role. Re-runnable: the GRANT statements are
-- idempotent on a fixed table set.
--
-- The grant set tracks the PG surface in
-- `server/lib/tuist/registry/swift/sync_worker.ex` and
-- `server/lib/tuist/registry/swift/release_worker.ex`. Both workers
-- only interact with Oban (consume :swift_registry_sync, insert
-- :swift_registry_release). Everything else they touch lives in S3,
-- not Postgres — so the grant is intentionally narrower than the
-- processor role (no `accounts` / `projects` reads).
--
-- Adding a new PG read or write in either worker means adding the
-- corresponding GRANT here in the same change.
--
-- See infra/cnpg/README.md for how to run this file against a fresh
-- cluster (or after a backup restore).

\if :{?tuist_schema}
\else
\set tuist_schema public
\endif

BEGIN;

GRANT CONNECT ON DATABASE tuist TO tuist_swift_registry_sync;
GRANT USAGE ON SCHEMA :"tuist_schema" TO tuist_swift_registry_sync;

-- Oban coordination. INSERT is needed because the SyncWorker enqueues
-- ReleaseWorker jobs; DELETE is needed for Oban.Plugins.Pruner.
GRANT SELECT, INSERT, UPDATE, DELETE ON :"tuist_schema".oban_jobs, :"tuist_schema".oban_peers TO tuist_swift_registry_sync;
GRANT USAGE, SELECT ON SEQUENCE :"tuist_schema".oban_jobs_id_seq TO tuist_swift_registry_sync;

-- Re-assert the intersection explicitly. New tables added by future
-- migrations stay off-limits until grants are re-issued here; the
-- REVOKE + re-GRANT pattern keeps the intent obvious. Notably absent:
-- `accounts` and `projects`, which the processor role can read but the
-- registry sync workers have no reason to touch (all package state
-- lives in S3, not scoped to any Tuist account).
REVOKE ALL ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_swift_registry_sync;
GRANT SELECT, INSERT, UPDATE, DELETE ON :"tuist_schema".oban_jobs, :"tuist_schema".oban_peers TO tuist_swift_registry_sync;

COMMIT;

-- Sanity check.
SELECT
  grantee, table_name,
  string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'tuist_swift_registry_sync' AND table_schema = :'tuist_schema'
GROUP BY grantee, table_name
ORDER BY table_name;
