defmodule Tuist.IngestRepo.Migrations.AddTestCaseIdToShardMv do
  @moduledoc """
  Recreates `test_case_runs_by_shard_id` with `test_case_id` and `ran_at`
  added, using the explicit TO-table pattern.

  Same rationale as the test_run MV: enables full primary key lookup on
  the main table (project_id, test_case_id, ran_at, id) after MV pagination,
  reducing reads from ~4.5M to ~20 rows.

  Uses an explicit storage table (`test_case_runs_by_shard_id`) with the
  MV trigger named `test_case_runs_by_shard_id_mv`. Backfills go directly
  into the storage table, avoiding the ZooKeeper "table is shutting down"
  race on ClickHouse Cloud.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_shard_id")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_by_shard_id (
      id UUID,
      shard_id UUID,
      name String,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      is_flaky Bool DEFAULT false,
      is_new Bool DEFAULT false,
      duration Int32,
      shard_index Nullable(Int32),
      project_id Int64,
      test_case_id Nullable(UUID),
      ran_at DateTime64(6)
    ) ENGINE = MergeTree
    ORDER BY (shard_id, name, id)
    """)

    backfill_by_partition()

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_shard_id_mv
    TO test_case_runs_by_shard_id
    AS SELECT
      id, assumeNotNull(shard_id) AS shard_id, name,
      status, is_flaky, is_new, duration, shard_index, project_id,
      test_case_id, ran_at
    FROM test_case_runs
    WHERE shard_id IS NOT NULL
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_shard_id_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_shard_id")

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
          (id, shard_id, name, status, is_flaky, is_new, duration, shard_index, project_id, test_case_id, ran_at)
        SELECT
          id, assumeNotNull(shard_id), name,
          status, is_flaky, is_new, duration, shard_index, project_id,
          test_case_id, ran_at
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND shard_id IS NOT NULL
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
