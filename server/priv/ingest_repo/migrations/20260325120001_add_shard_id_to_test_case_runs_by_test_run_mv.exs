defmodule Tuist.IngestRepo.Migrations.AddShardIdToTestCaseRunsByTestRunMv do
  @moduledoc """
  Recreates the `test_case_runs_by_test_run` materialized view to include
  `shard_id`. Sharded test runs filter by `shard_id` instead of `test_run_id`,
  and without this column the MV cannot serve those queries — causing 607 M+
  row full scans on the main table.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, id)
    AS SELECT id, test_run_id, status, is_flaky, duration, inserted_at, shard_id
    FROM test_case_runs
    """)

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, id)
    AS SELECT id, test_run_id, status, is_flaky, duration, inserted_at
    FROM test_case_runs
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_by_test_run")

      IngestRepo.query!(
        """
        INSERT INTO test_case_runs_by_test_run (id, test_run_id, status, is_flaky, duration, inserted_at, shard_id)
        SELECT id, test_run_id, status, is_flaky, duration, inserted_at, shard_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
