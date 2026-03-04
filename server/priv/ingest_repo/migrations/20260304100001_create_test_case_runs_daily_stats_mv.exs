defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsDailyStatsMv do
  @moduledoc """
  Creates a pre-aggregated materialized view for test_case_runs analytics.

  Project 1227 alone has ~41M test_case_runs in a 30-day window. Even with
  the unpartitioned `test_case_runs_by_inserted_at` MV sorted by
  (project_id, inserted_at), ClickHouse must still scan all 41M matching
  rows to compute count/avg/quantile aggregations.

  This AggregatingMergeTree MV pre-computes daily aggregates per
  (project_id, date, status, is_ci, is_flaky). A 30-day query now reads
  ~360 pre-aggregated rows instead of 41M raw rows.

  Covers all six analytics functions in `Tuist.Tests.Analytics` for
  daily, monthly, and total time buckets. Hourly queries (≤1 day range)
  still use the raw MV since they naturally cover a small date range.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_daily_stats
    ENGINE = AggregatingMergeTree
    ORDER BY (project_id, date, status, is_ci, is_flaky)
    POPULATE
    AS SELECT
      project_id,
      toDate(inserted_at) AS date,
      status,
      is_ci,
      is_flaky,
      countState() AS count_state,
      avgState(duration) AS avg_duration_state,
      quantileState(0.50)(duration) AS p50_duration_state,
      quantileState(0.90)(duration) AS p90_duration_state,
      quantileState(0.99)(duration) AS p99_duration_state
    FROM test_case_runs
    GROUP BY project_id, toDate(inserted_at), status, is_ci, is_flaky
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP VIEW IF EXISTS test_case_runs_daily_stats"
  end
end
