defmodule Tuist.IngestRepo.Migrations.AddProjectInsertedAtProjectionToTestCaseRuns do
  @moduledoc """
  Adds a `proj_by_project_inserted_at` projection for analytics queries of the form:

      SELECT formatDateTime(inserted_at, '%Y-%m-%d'), count(id) / avg(duration) / quantile(...)
      FROM test_case_runs
      WHERE project_id = ?
        AND inserted_at >= ?
        AND inserted_at <= ?
      GROUP BY 1

  This covers all six analytics functions in `Tuist.Tests.Analytics`:
  `test_case_run_count`, `test_case_run_total_count`, `test_case_run_aggregated_duration`,
  `test_case_run_duration_percentiles`, `test_case_run_average_durations`, and
  `test_case_run_percentile_durations`.

  Without this projection, ClickHouse falls back to `proj_test_case_runs_by_project_ran_at`
  (ORDER BY project_id, ran_at), which narrows to the right project but then scans all
  project rows because `inserted_at` is not sorted within the projection. For large
  projects this reads tens of millions of rows (46 M for project 1227, taking ~7 s).

  With `(project_id, inserted_at)` ordering ClickHouse can binary-search both the project
  boundary and the date-range boundary, reading only the rows that fall within the window.
  Local benchmarks with 5 M rows showed ~2.2× fewer rows read and ~44% lower latency for
  a typical 30-day window.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_project_inserted_at (
      SELECT project_id, inserted_at, id, status, is_ci, duration
      ORDER BY project_id, inserted_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_inserted_at"
  end
end
