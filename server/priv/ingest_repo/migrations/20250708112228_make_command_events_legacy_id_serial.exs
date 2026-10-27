defmodule Tuist.ClickHouseRepo.Migrations.MakeCommandEventsLegacyIDSerial do
  use Ecto.Migration

  def up do
    # `generateSerialID` needs a configured Keeper, which the managed instance
    # has and a single-node ClickHouse does not. Being hosted does not imply
    # having one: every preview environment is hosted and runs its own
    # Keeper-less ClickHouse, where these statements fail outright. Where serial
    # IDs are unavailable, legacy_id keeps the random default it was created
    # with.
    if Tuist.ClickHouseCapabilities.use_serial_ids?(repo()) do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      # Set the start of our serial to the maximum legacy_id in the command_events table.
      execute """
      WITH (SELECT max(legacy_id) AS seq_start FROM command_events) AS start_query_number
      SELECT number, generateSerialID('command_events_legacy_id')
      FROM numbers(toUInt64(COALESCE((start_query_number), 0)) + 1)
      """

      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      execute("""
      ALTER TABLE command_events
      MODIFY COLUMN legacy_id Int64 DEFAULT generateSerialID('command_events_legacy_id');;
      """)
    end
  end
end
