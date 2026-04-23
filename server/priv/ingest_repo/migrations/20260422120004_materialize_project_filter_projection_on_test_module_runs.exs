defmodule Tuist.IngestRepo.Migrations.MaterializeProjectFilterProjectionOnTestModuleRuns do
  @moduledoc """
  Materializes `proj_by_project_is_ci_branch_ran_at` across all existing
  parts of `test_module_runs`. The preceding migration only recorded the
  projection definition; this one does the slow part rewrite.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE test_module_runs
    MATERIALIZE PROJECTION proj_by_project_is_ci_branch_ran_at
    """
  end

  def down do
    :ok
  end
end
