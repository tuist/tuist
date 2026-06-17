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
-- Only needed for clusters that were already bootstrapped before query-stats
-- was enabled. Fresh clusters create the extension automatically via the
-- Cluster CR's `bootstrap.initdb.postInitSQL` (gated on queryStats.enabled),
-- and the extension persists across physical restores. A future CNPG >= 1.26
-- upgrade would let `Database.spec.extensions` reconcile this declaratively on
-- existing clusters too, retiring this file.
--
-- See infra/cnpg/README.md for how to run.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Sanity check: the view resolves and is readable.
SELECT count(*) AS statement_entries FROM pg_stat_statements;
