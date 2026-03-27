defmodule Tuist.IngestRepo.Migrations.AddProjectIdToShardIdMv do
  @moduledoc """
  Recreates `test_case_runs_by_shard_id` to include `project_id`.

  The 20-row ID lookup on the main table (`WHERE id IN (20 IDs)`) reads
  231M+ rows because the bloom filter on `id` isn't selective across many
  partitions. Adding `project_id` lets the lookup use the main table's PK
  prefix: `WHERE project_id = ? AND id IN (20 IDs)`.
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
      status, is_flaky, is_new, duration, shard_index, project_id
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
    ORDER BY (shard_id, name, id)
    AS SELECT
      id, assumeNotNull(shard_id) AS shard_id, name,
      status, is_flaky, is_new, duration, shard_index
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
          (id, shard_id, name, status, is_flaky, is_new, duration, shard_index, project_id)
        SELECT
          id, assumeNotNull(shard_id), name,
          status, is_flaky, is_new, duration, shard_index, project_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND shard_id IS NOT NULL
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
