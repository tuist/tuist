-- Optional read-only follow-up using an ALREADY authorized connection to
-- the maintenance database (postgres). The chart installs pg_stat_statements
-- there, not in tuist. Do not install it, reset it, or retrieve credentials
-- to run this. An absent extension or insufficient privileges is a stop.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5s';
SET LOCAL lock_timeout = '500ms';
SET LOCAL idle_in_transaction_session_timeout = '10s';
SELECT now() AS observed_at, stats_reset, dealloc FROM pg_stat_statements_info;
SELECT queryid, calls, rows, total_exec_time, mean_exec_time,
       shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written,
       wal_bytes, query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'tuist')
  AND query ILIKE '%oban_jobs%'
  AND query ~* '^(select|with|insert|update|delete)'
ORDER BY calls DESC LIMIT 40;
COMMIT;
-- Repeat in a fresh session at a recorded time for interval rates. This top-40
-- view is triage, not an exhaustive inventory; inspect low-frequency dashboard
-- and operator shapes before removing support for an operator or expression.
