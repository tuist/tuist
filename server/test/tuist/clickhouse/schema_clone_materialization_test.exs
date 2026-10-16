defmodule Tuist.ClickHouse.SchemaCloneMaterializationTest do
  # `system.parts`, `system.mutations` and `ALTER` are not supported inside the
  # ClickHouse transaction DataCase opens, so this runs unsandboxed against a
  # scratch table it creates and drops.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.ClickHouse.SchemaClone
  alias Tuist.IngestRepo

  setup do
    owner = Sandbox.start_owner!(IngestRepo, shared: true, sandbox: false)
    %{rows: [[database]]} = IngestRepo.query!("SELECT currentDatabase()")
    table = "schema_clone_materialization_#{System.unique_integer([:positive])}"

    on_exit(fn ->
      IngestRepo.query!("DROP TABLE IF EXISTS `#{table}`")
      Sandbox.stop_owner(owner)
    end)

    IngestRepo.query!("""
    CREATE TABLE `#{table}` (bucket UInt8, id UUID)
    ENGINE = MergeTree PARTITION BY bucket ORDER BY tuple()
    """)

    %{database: database, table: table}
  end

  test "finds the partitions written before an index was added until they are materialized", %{
    database: database,
    table: table
  } do
    IngestRepo.query!("INSERT INTO `#{table}` SELECT number % 2, generateUUIDv4() FROM numbers(10)")
    IngestRepo.query!("ALTER TABLE `#{table}` ADD INDEX idx_id id TYPE bloom_filter GRANULARITY 1")
    IngestRepo.query!("INSERT INTO `#{table}` SELECT 2, generateUUIDv4() FROM numbers(10)")

    assert SchemaClone.unindexed_partition_ids(IngestRepo, database, table) == ["0", "1"]
    assert SchemaClone.pending_materializations(IngestRepo, database, table, "idx_id") == []

    for statement <- SchemaClone.materialize_index_statements(database, table, "idx_id", ["0", "1"]) do
      IngestRepo.query!(statement)
    end

    assert eventually(fn ->
             SchemaClone.pending_materializations(IngestRepo, database, table, "idx_id") == [] and
               SchemaClone.unindexed_partition_ids(IngestRepo, database, table) == []
           end)
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(100)
        eventually(check, attempts - 1)
    end
  end
end
