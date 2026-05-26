-- Per-database privileges for the `tuist_ops_ro` role.
--
-- The role is created declaratively by CNPG via
-- `managed.roles[name=tuist_ops_ro]` with `inRoles: pg_read_all_data`,
-- so it already inherits SELECT on every present and future table. This
-- file ensures the role can `CONNECT` to the database (needed when the
-- bootstrap order means CNPG creates the role before the database has
-- been opened to non-superuser connections) and revokes anything the
-- pg_read_all_data predefined role would let it touch beyond reads.
--
-- The `/ops/db` LiveView in the Tuist server connects as this role so
-- every query the UI runs is authenticated by the cluster as a
-- read-only principal — even when an operator pastes a hand-written
-- SQL statement.

BEGIN;

GRANT CONNECT ON DATABASE tuist TO tuist_ops_ro;
GRANT USAGE ON SCHEMA public TO tuist_ops_ro;
GRANT USAGE ON SCHEMA pg_catalog TO tuist_ops_ro;
GRANT USAGE ON SCHEMA information_schema TO tuist_ops_ro;

-- Belt-and-braces: even though `pg_read_all_data` membership grants
-- SELECT on every table, explicitly REVOKE the write privileges so a
-- future grant-by-default change in Postgres can't widen the role.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public FROM tuist_ops_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLES FROM tuist_ops_ro;

COMMIT;

-- Sanity check.
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole
FROM pg_roles
WHERE rolname = 'tuist_ops_ro';
