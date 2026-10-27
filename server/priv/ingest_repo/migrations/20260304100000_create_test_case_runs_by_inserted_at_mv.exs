defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsByInsertedAtMv do
  @moduledoc """
  Creates a materialized view for efficient analytics queries on test_case_runs.

  The main `test_case_runs` table is a ReplacingMergeTree with
  PARTITION BY toYYYYMM(inserted_at) and ORDER BY (test_run_id, test_module_run_id, id).
  Analytics queries filter by (project_id, inserted_at range) and aggregate with
  count/avg/quantile. Even with the `proj_by_project_inserted_at` projection,
  these queries scan ~28M rows because projections inherit the parent table's
  monthly partitioning — ClickHouse must still read from every partition and
  merge the results.

  This materialized view stores the same data WITHOUT partitioning, sorted by
  (project_id, inserted_at). ClickHouse can binary-search directly to the
  target project and date range, reading only the matching rows.

  This covers the analytics functions in `Tuist.Tests.Analytics`:
  `test_case_run_count`, `test_case_run_total_count`,
  `test_case_run_aggregated_duration`, `test_case_run_duration_percentiles`,
  `test_case_run_average_durations`, and `test_case_run_percentile_durations`.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_inserted_at
    ENGINE = MergeTree
    ORDER BY (project_id, inserted_at)
    POPULATE
    AS SELECT * FROM test_case_runs
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS test_case_runs_by_inserted_at"
  end
end
