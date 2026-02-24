defmodule Tuist.IngestRepo.Migrations.AddProjectRanAtProjectionToTestCaseRuns do
  @moduledoc """
  Replaces `proj_by_project_analytics` with a new `proj_test_case_runs_by_project_ran_at` projection
  that includes all columns, ordered by `(project_id, ran_at)`.

  This optimizes the most common test case runs query:

      SELECT * FROM test_case_runs
      WHERE project_id = ?
      ORDER BY ran_at DESC
      LIMIT 20

  Without this projection, ClickHouse must scan all rows (100M+) because the table's
  ordering key `(test_run_id, test_module_run_id, inserted_at, id)` doesn't start
  with `project_id`. The old `proj_by_project_analytics` had the right ordering prefix
  but only included 6 columns, so ClickHouse couldn't use it for `SELECT *` queries.
  Since the new projection is a superset, the old one is no longer needed.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_analytics"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_test_case_runs_by_project_ran_at (
      SELECT *
      ORDER BY project_id, ran_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_test_case_runs_by_project_ran_at"
  end
end
