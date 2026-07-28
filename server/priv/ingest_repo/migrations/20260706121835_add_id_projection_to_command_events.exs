defmodule Tuist.IngestRepo.Migrations.AddIdProjectionToCommandEvents do
  @moduledoc """
  Adds an id-ordered projection to `command_events`.

  Production slow-query telemetry showed `get_command_event_by_id/1` issuing
  `WHERE id = ?` lookups against `command_events` thousands of times in a
  30-minute window. The table is ordered by `(project_id, name, ran_at)`, so an
  id-only predicate cannot use the primary key and was reading ~1.17M rows per
  lookup even with the existing `idx_id` bloom-filter skip index. An id-ordered
  projection gives ClickHouse a physical layout where those lookups can read in
  id order instead of scanning many wide granules.

  `ADD PROJECTION` is metadata-only. Materialization happens in the follow-up
  migration so the metadata change can propagate before the slower part rewrite
  runs.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    ALTER TABLE command_events
    ADD PROJECTION IF NOT EXISTS proj_by_id (
      SELECT *
      ORDER BY id
    )
    SETTINGS alter_sync = 2
    """
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "ALTER TABLE command_events DROP PROJECTION IF EXISTS proj_by_id"
  end
end
