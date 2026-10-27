defmodule Tuist.IngestRepo.Migrations.CreateDashboardCountMv do
  @moduledoc """
  Creates a pre-aggregated materialized view for global dashboard count queries.

  The dashboard functions (total_test_case_run_count, flaky_test_case_run_count,
  last_24h_test_case_run_count, last_24h_flaky_test_case_run_count) currently run
  `count(*) FINAL` over the entire test_case_runs table (37.6M rows, p50=474ms).

  This AggregatingMergeTree MV pre-computes daily counts by is_flaky flag,
  reducing dashboard queries from millions of rows to ~365 rows per year.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_dashboard_count
    ENGINE = AggregatingMergeTree
    ORDER BY (day, is_flaky)
    POPULATE
    AS SELECT
      toDate(inserted_at) AS day,
      is_flaky,
      countState() AS count
    FROM test_case_runs
    GROUP BY toDate(inserted_at), is_flaky
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS test_case_runs_dashboard_count"
  end
end
