defmodule Tuist.IngestRepo.Migrations.MaterializeIdProjectionOnBuildRuns do
  @moduledoc """
  Materializes `proj_by_id` across all existing parts of `build_runs`. The
  preceding migration only recorded the projection definition; this one
  does the part rewrite.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE build_runs
    MATERIALIZE PROJECTION proj_by_id
    """
  end

  def down do
    :ok
  end
end
