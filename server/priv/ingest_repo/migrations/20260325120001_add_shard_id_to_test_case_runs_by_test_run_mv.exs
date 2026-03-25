defmodule Tuist.IngestRepo.Migrations.AddShardIdToTestCaseRunsByTestRunMv do
  @moduledoc """
  Creates a dedicated `test_case_runs_by_shard_id` MV ordered by
  `(shard_id, id)` for efficient shard_id lookups.

  Sharded test runs filter by `shard_id` instead of `test_run_id`, and without
  a dedicated MV those queries cause 607 M+ row full scans on the main table.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_shard_id
    ENGINE = MergeTree
    ORDER BY (shard_id, id)
    AS SELECT id, assumeNotNull(shard_id) AS shard_id
    FROM test_case_runs
    WHERE shard_id IS NOT NULL
    """)

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_shard_id")
  end

  defp backfill_by_partition do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition
        """,
        %{table: "test_case_runs"}
      )

    for [partition] <- partitions do
      Logger.info("Backfilling partition #{partition} into test_case_runs_by_shard_id")

      IngestRepo.query!(
        """
        INSERT INTO test_case_runs_by_shard_id (id, shard_id)
        SELECT id, assumeNotNull(shard_id)
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND shard_id IS NOT NULL
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
