defmodule Tuist.IngestRepo.Migrations.AddProjectionsToBuildMachineMetrics do
  @moduledoc """
  Adds projections to speed up lookups by build_run_id and gradle_build_id.

  The table is ordered by (inserted_at, timestamp), so queries filtering by
  build_run_id or gradle_build_id would require a full table scan. These
  projections let ClickHouse binary-search directly to the matching rows.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_machine_metrics
    ADD PROJECTION proj_by_build_run_id (
      SELECT *
      ORDER BY build_run_id, timestamp
    )
    SETTINGS alter_sync = 2
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_machine_metrics
    ADD PROJECTION proj_by_gradle_build_id (
      SELECT *
      ORDER BY gradle_build_id, timestamp
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_machine_metrics DROP PROJECTION IF EXISTS proj_by_build_run_id"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE build_machine_metrics DROP PROJECTION IF EXISTS proj_by_gradle_build_id"
  end
end
