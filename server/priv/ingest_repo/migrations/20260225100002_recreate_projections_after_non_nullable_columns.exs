defmodule Tuist.IngestRepo.Migrations.RecreateProjectionsAfterNonNullableColumns do
  @moduledoc """
  Recreates the `proj_test_case_runs_by_project_ran_at` and `proj_by_project_flaky`
  projections after `project_id` and `ran_at` were changed to non-nullable.

  Non-nullable ORDER BY columns and explicit column lists (instead of `SELECT *`)
  allow the ClickHouse query optimizer to reliably use these projections, fixing
  the performance issue where queries like `WHERE project_id = ? ORDER BY ran_at DESC`
  scanned tens of millions of rows.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_test_case_runs_by_project_ran_at (
      SELECT id, name, test_run_id, test_module_run_id, test_suite_run_id,
             status, duration, module_name, suite_name, inserted_at,
             project_id, is_ci, scheme, account_id, ran_at,
             git_branch, test_case_id, git_commit_sha, is_flaky, is_new
      ORDER BY project_id, ran_at
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_case_runs
    ADD PROJECTION proj_by_project_flaky (
      SELECT id, project_id, is_flaky, test_case_id, test_run_id, inserted_at
      ORDER BY project_id, is_flaky, test_case_id, inserted_at
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_test_case_runs_by_project_ran_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_flaky"
  end
end
