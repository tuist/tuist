-- Per-database privileges for the `tuist_ops_ro` role.
--
-- The role is created declaratively by CNPG via
-- `managed.roles[name=tuist_ops_ro]` with `inRoles: pg_read_all_data`,
-- so it already inherits SELECT on every present and future table. This
-- file ensures the role can `CONNECT` to the database (needed when the
-- bootstrap order means CNPG creates the role before the database has
-- been opened to non-superuser connections) and explicitly revokes
-- write privileges so a future grant-by-default change in Postgres
-- can't widen the role.
--
-- Used by operators who open an ad-hoc psql session against the cluster
-- (typically `kubectl cnpg psql ... -U tuist_ops_ro`) for break-glass
-- inspection that doesn't fit the `/ops/db` LiveView. The LiveView
-- itself connects through Tuist.Repo (the web runtime role) and enforces
-- read-only behavior at the app layer: SELECT/WITH/EXPLAIN/SHOW grammar
-- gate plus `SET TRANSACTION READ ONLY` plus a 5s `statement_timeout`.
-- See `Tuist.Ops.Database.execute/2`.

\if :{?tuist_schema}
\else
\set tuist_schema public
\endif

BEGIN;

GRANT CONNECT ON DATABASE tuist TO tuist_ops_ro;
GRANT USAGE ON SCHEMA :"tuist_schema" TO tuist_ops_ro;
GRANT USAGE ON SCHEMA pg_catalog TO tuist_ops_ro;
GRANT USAGE ON SCHEMA information_schema TO tuist_ops_ro;

-- NOTE: the web runtime role's membership in tuist_ops_ro (so the internal
-- Atlas query runner can `SET ROLE tuist_ops_ro`) is managed declaratively by
-- CNPG via `managed.roles[tuist_web].inRoles` + `inherit: false` in
-- infra/helm/tuist/templates/postgresql-cnpg.yaml — CNPG reconciles it, so there
-- is no manual GRANT here.

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA :"tuist_schema" FROM tuist_ops_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA :"tuist_schema"
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLES FROM tuist_ops_ro;

COMMIT;

-- Sanity check.
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles
WHERE rolname = 'tuist_ops_ro';
