defmodule Tuist.IngestRepo.Migrations.MaterializeRecreatedProjections do
  @moduledoc """
  Materializes the recreated projections for existing data parts.
  Separated from projection creation so new inserts benefit immediately.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_test_case_runs_by_project_ran_at SETTINGS mutations_sync = 1"

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE test_case_runs MATERIALIZE PROJECTION proj_by_project_flaky SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
