defmodule Tuist.IngestRepo.Migrations.MakeProjectIdAndRanAtNonNullableInTestCaseRuns do
  @moduledoc """
  Drops projections that reference `project_id` and `ran_at` so that
  subsequent migrations can change the column types.

  Split into its own migration so that on retry the DROP PROJECTIONs
  are not re-queued as duplicate mutations.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_test_case_runs_by_project_ran_at"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs DROP PROJECTION IF EXISTS proj_by_project_flaky"
  end

  def down do
    :ok
  end
end
