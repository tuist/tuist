-- Auth-query bootstrap for the CNPG Pooler (PgBouncer).
--
-- CNPG's Pooler runs PgBouncer with `auth_user = cnpg_pooler_pgbouncer`
-- and `auth_query = SELECT usename, passwd FROM user_search($1)`. Neither
-- the role nor the function is created by the operator, so PgBouncer
-- cannot authenticate any application role until this file has run. Run
-- it ONCE per fresh cluster, as the cluster superuser, against the
-- application database, BEFORE flipping `postgresql.cnpg.pooler.enabled`
-- to true in the env values. Enabling the Pooler without this leaves the
-- processor unable to connect.
--
-- Re-runnable: the role create is guarded and the function uses
-- CREATE OR REPLACE.
--
-- See infra/cnpg/README.md for the `kubectl cnpg psql` invocation.

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cnpg_pooler_pgbouncer') THEN
    CREATE ROLE cnpg_pooler_pgbouncer WITH LOGIN;
  END IF;
END
$$;

-- SECURITY DEFINER so the (unprivileged) auth role can read pg_shadow
-- through this function without being granted broad access itself.
CREATE OR REPLACE FUNCTION public.user_search(uname TEXT)
  RETURNS TABLE (usename name, passwd text)
  LANGUAGE sql
  SECURITY DEFINER
  AS 'SELECT usename, passwd FROM pg_catalog.pg_shadow WHERE usename = $1;';

REVOKE ALL ON FUNCTION public.user_search(text) FROM public;
GRANT EXECUTE ON FUNCTION public.user_search(text) TO cnpg_pooler_pgbouncer;
