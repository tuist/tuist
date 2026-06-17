-- Enable pg_stat_statements so the instance metrics exporter can expose
-- per-query latency as Prometheus metrics (cnpg_tuist_query_stats_*, via the
-- monitoring ConfigMap rendered by
-- infra/helm/tuist/templates/postgresql-cnpg-monitoring-queries.yaml).
--
-- The library is already preloaded via spec.postgresql.shared_preload_libraries
-- (postgresql.cnpg.sharedPreloadLibraries in the chart values); this file
-- creates the extension so the reading view exists.
--
-- Run against the `postgres` maintenance database, NOT `tuist`:
-- pg_stat_statements is instance-global (one shared-memory hash across all
-- databases) and the metrics exporter queries it from `postgres`, so the view
-- must exist there. The query in the ConfigMap filters to the application
-- database's statements by dbid. Idempotent and re-runnable.
--
-- See infra/cnpg/README.md for how to run.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Sanity check: the view resolves and is readable.
SELECT count(*) AS statement_entries FROM pg_stat_statements;
