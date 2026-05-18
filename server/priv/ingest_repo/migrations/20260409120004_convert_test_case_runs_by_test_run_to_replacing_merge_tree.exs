defmodule Tuist.IngestRepo.Migrations.ConvertTestCaseRunsByTestRunToReplacingMergeTree do
  @moduledoc """
  Converts the `test_case_runs_by_test_run` table from MergeTree to
  ReplacingMergeTree(inserted_at).

  The source table `test_case_runs` is ReplacingMergeTree, so re-inserts (e.g.
  flaky flag updates) produce duplicate rows in the MV. With a plain MergeTree
  engine, those duplicates are never merged and aggregate queries (count, avg)
  over-count. ReplacingMergeTree + FINAL in read queries fixes this.

  Uses the explicit TO-table pattern introduced by the preceding migration
  (20260409120002). Drops both the MV trigger and storage table, recreates the
  storage table with the new engine, backfills, then recreates the MV trigger.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(id test_run_id status is_flaky is_new duration inserted_at ran_at name project_id test_case_id)

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_test_run")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_by_test_run (
      id UUID,
      test_run_id UUID,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      is_flaky Bool DEFAULT false,
      is_new Bool DEFAULT false,
      duration Int32,
      inserted_at DateTime64(6),
      ran_at DateTime64(6),
      name String,
      project_id Int64,
      test_case_id Nullable(UUID)
    ) ENGINE = ReplacingMergeTree(inserted_at)
    ORDER BY (test_run_id, ran_at, id)
    """)

    backfill_by_partition()

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run_mv
    TO test_case_runs_by_test_run
    AS SELECT #{Enum.join(@columns, ", ")}
    FROM test_case_runs
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_by_test_run_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_by_test_run")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_by_test_run (
      id UUID,
      test_run_id UUID,
      status Enum8('success' = 0, 'failure' = 1, 'skipped' = 2),
      is_flaky Bool DEFAULT false,
      is_new Bool DEFAULT false,
      duration Int32,
      inserted_at DateTime64(6),
      ran_at DateTime64(6),
      name String,
      project_id Int64,
      test_case_id Nullable(UUID)
    ) ENGINE = MergeTree
    ORDER BY (test_run_id, ran_at, id)
    """)

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run_mv
    TO test_case_runs_by_test_run
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

      retry_on_shutting_down(fn ->
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
      end)
    end
  end

  defp retry_on_shutting_down(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      if attempts > 1 and String.contains?(to_string(e.message), "TABLE_IS_READ_ONLY") do
        Logger.warning("Table is shutting down, retrying in 5s (#{attempts - 1} attempts left)")
        Process.sleep(:timer.seconds(5))
        retry_on_shutting_down(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
