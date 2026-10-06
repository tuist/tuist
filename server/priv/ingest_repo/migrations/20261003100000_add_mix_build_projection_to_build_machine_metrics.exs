defmodule Tuist.IngestRepo.Migrations.AddMixBuildProjectionToBuildMachineMetrics do
  @moduledoc """
  Adds a projection to look up machine samples by mix_build_id, like the ones
  for build_run_id and gradle_build_id. Without it, opening a Mix build scans
  the samples of every build in the table.

  Nothing to materialize: rows written before this branch have no
  mix_build_id, so only new inserts belong in the projection.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_machine_metrics
    ADD PROJECTION IF NOT EXISTS proj_by_mix_build_id (
      SELECT *
      ORDER BY mix_build_id, timestamp
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_machine_metrics DROP PROJECTION IF EXISTS proj_by_mix_build_id"
  end
end
