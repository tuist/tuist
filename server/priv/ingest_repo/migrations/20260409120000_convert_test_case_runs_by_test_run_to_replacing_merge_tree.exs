defmodule Tuist.IngestRepo.Migrations.ConvertTestCaseRunsByTestRunToReplacingMergeTree do
  @moduledoc """
  Converts the `test_case_runs_by_test_run` materialized view from MergeTree to
  ReplacingMergeTree(inserted_at).

  The source table `test_case_runs` is ReplacingMergeTree, so re-inserts (e.g.
  flaky flag updates) produce duplicate rows in the MV. With a plain MergeTree
  engine, those duplicates are never merged and aggregate queries (count, avg)
  over-count. ReplacingMergeTree + FINAL in read queries fixes this.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(id test_run_id status is_flaky is_new duration inserted_at ran_at name project_id)

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY (test_run_id, ran_at, id)
    AS SELECT #{Enum.join(@columns, ", ")}
    FROM test_case_runs
    """)

    backfill_by_partition()
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run")

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, ran_at, id)
    AS SELECT #{Enum.join(@columns, ", ")}
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
        INSERT INTO test_case_runs_by_test_run (#{Enum.join(@columns, ", ")})
        SELECT #{Enum.join(@columns, ", ")}
        FROM test_case_runs FINAL
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        """,
        %{partition: String.to_integer(partition)},
        timeout: 1_200_000
      )
    end
  end
end
