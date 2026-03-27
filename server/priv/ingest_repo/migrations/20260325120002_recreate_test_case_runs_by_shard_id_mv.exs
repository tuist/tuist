defmodule Tuist.IngestRepo.Migrations.RecreateTestCaseRunsByShardIdMv do
  @moduledoc """
  Recreates the `test_case_runs_by_shard_id` MV with additional columns needed
  for filtering and sorting. The previous version only stored `(id, shard_id)`,
  which forced the main table lookup via `id IN (huge set)` — too slow because
  a single shard can match tens of thousands of rows and the bloom filter on
  `id` degenerates to a full scan.

  With the extra columns, we can paginate and count directly on the MV, then
  fetch only the 20 displayed rows from the main table by ID.

  Only rows with non-null shard_id are stored.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_shard_id")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_shard_id
    ENGINE = MergeTree
    ORDER BY (shard_id, name, id)
    AS SELECT
      id, assumeNotNull(shard_id) AS shard_id, name,
      status, is_flaky, is_new, duration, shard_index
    FROM test_case_runs
    WHERE shard_id IS NOT NULL
    """)

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_shard_id")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_shard_id
    ENGINE = MergeTree
    ORDER BY (shard_id, id)
    AS SELECT id, assumeNotNull(shard_id) AS shard_id
    FROM test_case_runs
    WHERE shard_id IS NOT NULL
    """)
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
        INSERT INTO test_case_runs_by_shard_id
          (id, shard_id, name, status, is_flaky, is_new, duration, shard_index)
        SELECT
          id, assumeNotNull(shard_id), name,
          status, is_flaky, is_new, duration, shard_index
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND shard_id IS NOT NULL
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
