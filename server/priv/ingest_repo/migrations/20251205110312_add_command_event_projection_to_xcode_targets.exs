defmodule Tuist.IngestRepo.Migrations.AddCommandEventProjectionToXcodeTargets do
  use Ecto.Migration

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE xcode_targets
    ADD PROJECTION proj_by_command_event (
      SELECT *
      ORDER BY command_event_id
    )
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets MATERIALIZE PROJECTION proj_by_command_event"
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE xcode_targets DROP PROJECTION IF EXISTS proj_by_command_event"
  end
end
