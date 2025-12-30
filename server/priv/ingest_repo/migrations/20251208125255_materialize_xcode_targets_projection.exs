defmodule Tuist.IngestRepo.Migrations.MaterializeXcodeTargetsProjection do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE PROJECTION proj_by_command_event"
  end

  def down do
    # Materialization cannot be undone - the projection will remain materialized
    :ok
  end
end
