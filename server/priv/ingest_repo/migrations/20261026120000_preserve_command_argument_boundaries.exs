defmodule Tuist.IngestRepo.Migrations.PreserveCommandArgumentBoundaries do
  use Ecto.Migration

  alias Tuist.IngestRepo

  @disable_ddl_transaction true
  @disable_migration_lock true
  @columns [{"command_arguments_array", "Array(String)"}, {"command_arguments_recorded", "Bool"}]

  def up do
    # Named inserts from older replicas omit these columns and retain the unknown defaults.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    ALTER TABLE command_events
      ADD COLUMN IF NOT EXISTS command_arguments_array Array(String) DEFAULT [],
      ADD COLUMN IF NOT EXISTS command_arguments_recorded Bool DEFAULT false
    """)

    verify_columns!()
  end

  def down do
    # Roll back every consumer before removing columns selected by the Event schema.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    ALTER TABLE command_events
      DROP COLUMN IF EXISTS command_arguments_array,
      DROP COLUMN IF EXISTS command_arguments_recorded
    """)
  end

  @doc false
  def verify_columns!(timeout_ms \\ 60_000) do
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")
    database = "'#{String.replace(database, "'", "''")}'"

    %{rows: clusters} =
      IngestRepo.query!("SELECT 1 FROM system.clusters WHERE cluster = 'default' LIMIT 1")

    clustered? = clusters != []

    replica_source =
      if clustered?, do: "clusterAllReplicas(default, system.one)", else: "system.one"

    %{rows: replicas} =
      IngestRepo.query!(
        "SELECT DISTINCT hostName() FROM #{replica_source} SETTINGS skip_unavailable_shards = 0"
      )

    if replicas == [] do
      raise Ecto.MigrationError, "ClickHouse replica discovery returned no replicas"
    end

    columns_source =
      if clustered?, do: "clusterAllReplicas(default, system.columns)", else: "system.columns"

    expected = for [replica] <- replicas, {name, type} <- @columns, do: {replica, name, type}
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_columns!(database, columns_source, expected, deadline)
  end

  defp wait_for_columns!(database, source, expected, deadline) do
    %{rows: rows} =
      IngestRepo.query!("""
      SELECT DISTINCT hostName(), name, type FROM #{source}
      WHERE database = #{database} AND table = 'command_events'
        AND name IN ('command_arguments_array', 'command_arguments_recorded')
      SETTINGS skip_unavailable_shards = 0, max_execution_time = 10
      """)

    present = MapSet.new(rows, &List.to_tuple/1)
    missing = Enum.reject(expected, &MapSet.member?(present, &1))
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      missing == [] ->
        :ok

      remaining <= 0 ->
        raise Ecto.MigrationError,
              "command argument columns are not ready on every ClickHouse replica: #{inspect(missing)}"

      true ->
        Process.sleep(min(250, remaining))
        wait_for_columns!(database, source, expected, deadline)
    end
  end
end
