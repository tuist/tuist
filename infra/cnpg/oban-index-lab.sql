-- LOCAL EXPERIMENT ONLY. Requires a fresh, disposable database named
-- oban_index_lab on a local PostgreSQL 16 instance. No production data.
-- Run with psql -X -v ON_ERROR_STOP=1 -d oban_index_lab -f this-file.sql.
\set ON_ERROR_STOP on
SELECT current_database() = 'oban_index_lab'
  AND (inet_server_addr() IS NULL OR inet_server_addr() IN ('127.0.0.1'::inet, '::1'::inet))
  AND current_setting('server_version_num')::int BETWEEN 160000 AND 169999 AS safe_database \gset
\if :safe_database
\else
  \echo 'Refusing: use a disposable local PostgreSQL 16 database named oban_index_lab.'
  DO $$ BEGIN RAISE EXCEPTION 'Unsafe experiment target'; END $$;
\endif

-- Deliberately fail on rerun instead of deleting an existing schema.
CREATE SCHEMA oban_index_lab;
SET search_path = oban_index_lab, public;
SET statement_timeout = '60s';
SET lock_timeout = '2s';
CREATE EXTENSION IF NOT EXISTS pgstattuple WITH SCHEMA public;

SELECT version(), current_setting('shared_buffers'), current_setting('maintenance_work_mem');

CREATE TABLE measurements (
  variant text, phase text, generation int, index_bytes bigint,
  pending_pages int, pending_tuples bigint, observed_at timestamptz DEFAULT clock_timestamp()
);

-- 70% small repeated alert keys, 20% unique dispatch envelopes with 60
-- high-cardinality payload strings, 10% small build references. This models
-- churn, not the exact production distribution or GitHub payload schema.
CREATE FUNCTION synthetic_args(i int) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN i % 10 < 7 THEN jsonb_build_object('alert_id', md5((i % 500)::text))
    WHEN i % 10 < 9 THEN jsonb_build_object(
      'delivery_guid', md5(i::text), 'installation_id', i % 20,
      'payload', (SELECT jsonb_object_agg('field_' || k, repeat(md5(i || ':' || k), 3))
                  FROM generate_series(1, 60) k))
    ELSE jsonb_build_object('build_id', md5(i::text), 'project_id', i % 50) END
$$;

CREATE TABLE variants (name text, expression text, storage text);
INSERT INTO variants VALUES
  ('full_ops', 'args jsonb_ops', ''),
  ('full_path_ops', 'args jsonb_path_ops', ''),
  ('without_payload_ops', '(args - ''payload'') jsonb_ops', ''),
  ('full_ops_fastupdate_off', 'args jsonb_ops', 'WITH (fastupdate=off)');

SELECT format('CREATE TABLE %I (id bigint PRIMARY KEY, generation int, state text, args jsonb) WITH (autovacuum_enabled=false)', name)
FROM variants \gexec
SELECT format('CREATE INDEX %I ON %I (state)', name || '_state', name) FROM variants \gexec
SELECT format('CREATE INDEX %I ON %I USING gin (%s) %s', name || '_args', name, expression, storage)
FROM variants \gexec

-- Each emitted statement runs in its own transaction, including each VACUUM.
-- Six generations of 3,000 jobs; retain only the most recent generation.
-- Indexed state transitions intentionally prevent HOT updates, like Oban.
\timing on
SELECT command FROM variants v CROSS JOIN generate_series(1, 6) g
CROSS JOIN LATERAL (VALUES
  (1, format('INSERT INTO %I SELECT i, %s, ''available'', synthetic_args(i) FROM generate_series(%s, %s) i', v.name, g, (g-1)*3000+1, g*3000)),
  (2, format('UPDATE %I SET state=''executing'' WHERE generation=%s', v.name, g)),
  (3, format('UPDATE %I SET state=''completed'' WHERE generation=%s', v.name, g)),
  (4, format('DELETE FROM %I WHERE generation < %s', v.name, g)),
  (5, format('INSERT INTO measurements SELECT %L, ''before_vacuum'', %s, pg_relation_size(%L), pending_pages, pending_tuples FROM public.pgstatginindex(%L)', v.name, g, v.name || '_args', v.name || '_args')),
  (6, format('VACUUM (VERBOSE, ANALYZE) %I', v.name)),
  (7, format('INSERT INTO measurements SELECT %L, ''after_vacuum'', %s, pg_relation_size(%L), pending_pages, pending_tuples FROM public.pgstatginindex(%L)', v.name, g, v.name || '_args', v.name || '_args'))
) commands(ordinal, command)
ORDER BY v.name, g, ordinal \gexec

-- Same-opclass concurrent rebuild on LOCAL synthetic tables only. Measure
-- shrinkage after ordinary vacuum has already removed dead row references.
SELECT format('REINDEX INDEX CONCURRENTLY %I', name || '_args') FROM variants \gexec
SELECT format('INSERT INTO measurements SELECT %L, ''after_reindex'', 6, pg_relation_size(%L), pending_pages, pending_tuples FROM public.pgstatginindex(%L)', name, name || '_args', name || '_args')
FROM variants \gexec
\timing off
TABLE measurements;

-- Compare an Oban-shaped containment lookup. The expression index deliberately
-- requires a query rewrite; PostgreSQL cannot substitute it for args @> ... .
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM full_ops
WHERE state='completed' AND args @> jsonb_build_object('delivery_guid', md5('17998')) LIMIT 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM full_path_ops
WHERE state='completed' AND args @> jsonb_build_object('delivery_guid', md5('17998')) LIMIT 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM without_payload_ops
WHERE state='completed' AND args @> jsonb_build_object('delivery_guid', md5('17998')) LIMIT 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM without_payload_ops
WHERE state='completed' AND (args - 'payload') @> jsonb_build_object('delivery_guid', md5('17998')) LIMIT 1;

-- Equal results for top-level and nested containment across full opclasses.
-- These assertions do not qualify arbitrary dashboard queries, concurrency,
-- production throughput, or the application-level deduplication contract.
DO $$
DECLARE candidate text; actual bigint[]; expected bigint[];
BEGIN
  SELECT array_agg(id ORDER BY id) INTO expected FROM full_ops
    WHERE args @> jsonb_build_object('delivery_guid', md5('17998'));
  IF expected IS DISTINCT FROM ARRAY[17998::bigint] THEN
    RAISE EXCEPTION 'fixture lookup failed';
  END IF;
  FOR candidate IN SELECT name FROM variants LOOP
    EXECUTE format('SELECT array_agg(id ORDER BY id) FROM %I WHERE args @> $1', candidate)
      INTO actual USING jsonb_build_object('delivery_guid', md5('17998'));
    IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'top-level mismatch: %', candidate; END IF;
    EXECUTE format('SELECT array_agg(id ORDER BY id) FROM %I WHERE args @> $1', candidate)
      INTO actual USING jsonb_build_object('payload', jsonb_build_object('field_1', repeat(md5('17998:1'),3)));
    IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'nested mismatch: %', candidate; END IF;
  END LOOP;
END $$;
