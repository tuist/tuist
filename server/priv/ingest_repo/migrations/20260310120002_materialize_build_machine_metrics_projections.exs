defmodule Tuist.IngestRepo.Migrations.MaterializeBuildMachineMetricsProjections do
  @moduledoc """
  Materializes the build_machine_metrics projections for existing data parts.
  Separated from the projection creation so new inserts benefit immediately.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_machine_metrics MATERIALIZE PROJECTION proj_by_build_run_id SETTINGS mutations_sync = 1"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_machine_metrics MATERIALIZE PROJECTION proj_by_gradle_build_id SETTINGS mutations_sync = 1"
  end

  def down do
    :ok
  end
end
