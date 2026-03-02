defmodule Tuist.IngestRepo.Migrations.BackfillCommandEventsByRanAt do
  @moduledoc """
  Backfills historical data into the recreated `command_events_by_ran_at`
  materialized view. Separated from the DDL migration so the view structure
  is applied first and new writes flow immediately.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "INSERT INTO command_events_by_ran_at SELECT * FROM command_events"
  end

  def down do
    :ok
  end
end
