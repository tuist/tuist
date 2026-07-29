defmodule Tuist.IngestRepo.Migrations.MaterializeIdProjectionOnCommandEvents do
  @moduledoc """
  Materializes `command_events.proj_by_id` for existing parts.

  The preceding migration adds the projection metadata. This migration starts
  the part rewrite separately to avoid racing replica metadata propagation.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE command_events
    MATERIALIZE PROJECTION proj_by_id
    """
  end

  def down do
    :ok
  end
end
