defmodule Tuist.IngestRepo.Migrations.AddCommandEventProjectionToXcodeTargets do
  use Ecto.Migration

  def up do
    # Add projection ordered by command_event_id for efficient filtering
    # This optimizes queries that filter by command_event_id on the xcode_targets table
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD PROJECTION proj_by_command_event (
      SELECT *
      ORDER BY command_event_id
    )
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS proj_by_command_event"
  end
end
