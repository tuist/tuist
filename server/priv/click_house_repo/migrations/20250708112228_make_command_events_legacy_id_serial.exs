defmodule Tuist.ClickHouseRepo.Migrations.MakeCommandEventsLegacyIDSerial do
  use Ecto.Migration

  def up do
    # This migration requires Zookeeper, which we are not using in dev/test environments. Therefore, only run it in deployment environments.
    if Tuist.Environment.dev?() || Tuist.Environment.test?() do
      :ok
    else
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
