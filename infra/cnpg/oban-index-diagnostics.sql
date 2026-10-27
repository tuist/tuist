-- Read-only PostgreSQL 16 diagnostics. No extensions or maintenance commands.
-- Use an already-authorized read-only connection to the tuist database:
-- psql -X -v ON_ERROR_STOP=1 -f infra/cnpg/oban-index-diagnostics.sql
-- For Atlas, submit the individual SELECTs through query_tuist_postgres,
-- which supplies its own read-only transaction and five-second timeout.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '500ms';
SET LOCAL idle_in_transaction_session_timeout = '10s';

SELECT now() AS observed_at, current_database(), pg_is_in_recovery(), version(), stats_reset
FROM pg_stat_database WHERE datname = current_database();

-- Missing rows/NULL fields in activity and settings views may reflect role
-- visibility. Never treat those as evidence that no maintenance is running.
SELECT pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') AS can_read_all_stats;

SELECT c.oid::regclass AS index_name, am.amname, op.opcname,
       pg_relation_size(c.oid) AS bytes, c.relpages, c.reltuples, c.reloptions,
       i.indisvalid, i.indisready, pg_get_indexdef(c.oid) AS definition,
       s.idx_scan, s.idx_tup_read, s.idx_tup_fetch
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_am am ON am.oid = c.relam
CROSS JOIN LATERAL unnest(i.indclass) WITH ORDINALITY AS oc(oid, position)
JOIN pg_opclass op ON op.oid = oc.oid
LEFT JOIN pg_stat_user_indexes s ON s.indexrelid = c.oid
WHERE i.indrelid = 'public.oban_jobs'::regclass
ORDER BY c.relname, oc.position;

SELECT now() AS observed_at, obj_description(c.oid, 'pg_class') AS oban_schema_version,
       c.reloptions, c.reltuples, c.relpages,
       pg_relation_size(c.oid) AS heap_bytes,
       pg_total_relation_size(c.reltoastrelid) AS toast_bytes,
       s.n_live_tup, s.n_dead_tup, s.n_tup_ins, s.n_tup_upd, s.n_tup_hot_upd, s.n_tup_del,
       s.last_autovacuum, s.autovacuum_count, s.last_autoanalyze
FROM pg_class c JOIN pg_stat_user_tables s ON s.relid = c.oid
WHERE c.oid = 'public.oban_jobs'::regclass;

SELECT name, setting, unit, source FROM pg_settings
WHERE name IN (
  'autovacuum_vacuum_scale_factor', 'autovacuum_vacuum_threshold',
  'autovacuum_vacuum_insert_scale_factor', 'autovacuum_vacuum_insert_threshold',
  'autovacuum_vacuum_cost_delay', 'autovacuum_vacuum_cost_limit',
  'vacuum_cost_limit', 'autovacuum_work_mem', 'maintenance_work_mem',
  'gin_pending_list_limit', 'autovacuum_naptime', 'autovacuum_max_workers',
  'log_autovacuum_min_duration', 'track_io_timing', 'shared_preload_libraries'
) ORDER BY name;

SELECT extname, extversion, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname IN ('pg_stat_statements', 'pgstattuple', 'pageinspect');

SELECT attname, avg_width, n_distinct, null_frac
FROM pg_stats WHERE schemaname = 'public' AND tablename = 'oban_jobs';

SELECT now() AS observed_at, pid, phase, heap_blks_total, heap_blks_scanned,
       heap_blks_vacuumed, index_vacuum_count, max_dead_tuples, num_dead_tuples
FROM pg_stat_progress_vacuum WHERE relid = 'public.oban_jobs'::regclass;
COMMIT;

-- Optional bounded sample, separate from metadata. SYSTEM samples heap pages,
-- so this is clustered and may miss rare/large jobs; it is not a population
-- count. LIMIT alone would not bound a full-table aggregation. No argument
-- values, identifiers, errors, URLs, or payloads leave the database.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '500ms';
SET LOCAL idle_in_transaction_session_timeout = '10s';
WITH sample AS MATERIALIZED (
  SELECT worker, state, args, scheduled_at, cancelled_at, discarded_at
  FROM public.oban_jobs TABLESAMPLE SYSTEM (1) REPEATABLE (2710)
  LIMIT 2500
)
SELECT worker, state, count(*) AS sampled_jobs,
       round(avg(pg_column_size(args))) AS avg_stored_args_bytes,
       max(pg_column_size(args)) AS max_stored_args_bytes,
       round(avg(octet_length(args::text))) AS avg_json_bytes,
       max(octet_length(args::text)) AS max_json_bytes,
       round(avg(octet_length((args - 'payload')::text))) AS avg_without_payload_bytes,
       count(*) FILTER (WHERE
         (state = 'completed' AND scheduled_at < now() - interval '2 hours') OR
         (state = 'cancelled' AND cancelled_at < now() - interval '2 hours') OR
         (state = 'discarded' AND discarded_at < now() - interval '2 hours')
       ) AS sampled_prune_eligible
FROM sample GROUP BY worker, state ORDER BY sampled_jobs DESC;
COMMIT;
