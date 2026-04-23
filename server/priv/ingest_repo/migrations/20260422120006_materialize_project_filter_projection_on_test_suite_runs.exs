defmodule Tuist.IngestRepo.Migrations.MaterializeProjectFilterProjectionOnTestSuiteRuns do
  @moduledoc """
  Materializes `proj_by_project_is_ci_branch_ran_at` across all existing
  parts of `test_suite_runs`. This is the slow part of the projection
  rollout; `test_suite_runs` is the largest of the two tables.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_suite_runs
    MATERIALIZE PROJECTION proj_by_project_is_ci_branch_ran_at
    """
  end

  def down do
    :ok
  end
end
