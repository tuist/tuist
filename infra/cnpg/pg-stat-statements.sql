-- Enable pg_stat_statements so the instance metrics exporter can expose
-- per-query latency as Prometheus metrics (cnpg_tuist_query_stats_*, via the
-- monitoring ConfigMap rendered by
-- infra/helm/tuist/templates/postgresql-cnpg-monitoring-queries.yaml).
--
-- The library is already preloaded via spec.postgresql.shared_preload_libraries
-- (postgresql.cnpg.sharedPreloadLibraries in the chart values); this file
-- creates the extension so the reading view exists.
--
-- Run against the configured application database (`tuist` by default).
-- pg_stat_statements is instance-global, but its SQL view must exist in the
-- database the exporter connects to. The query filters statements by dbid.
--
-- Manual recovery fallback only: the chart's Database CR (CNPG >= 1.26)
-- reconciles this extension on existing clusters, and fresh clusters install
-- it via bootstrap.initdb.postInitApplicationSQL. The view stays in public
-- regardless of the application's configured schema.
--
-- See infra/cnpg/README.md for how to run.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;

-- Sanity check: the view resolves and is readable.
SELECT count(*) AS statement_entries FROM public.pg_stat_statements;
