defmodule Tuist.IngestRepo.Migrations.AddTestCaseIdToTestRunMv do
  @moduledoc """
  Recreates `test_case_runs_by_test_run` with `test_case_id` added,
  using the explicit TO-table pattern.

  After MV pagination, the code fetches full rows from the main table:
    WHERE project_id IN (...) AND id IN (...)

  The main table ORDER BY is (project_id, test_case_id, ran_at, id).
  With only project_id + id, ClickHouse cannot binary-search efficiently
  (4.5M rows read, p50 = 1.6s).

  By adding test_case_id (and ran_at which is already present), the lookup
  can match the primary key prefix (project_id, test_case_id),
  reducing reads from ~4.5M to ~20 rows.

  Uses an explicit storage table (`test_case_runs_by_test_run`) with the
  MV trigger named `test_case_runs_by_test_run_mv`. Backfills go directly
  into the storage table, avoiding the ZooKeeper "table is shutting down"
  race on ClickHouse Cloud.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns ~w(id test_run_id status is_flaky is_new duration inserted_at ran_at name project_id test_case_id)

  def up do
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
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_by_test_run
    ENGINE = MergeTree
    ORDER BY (test_run_id, ran_at, id)
    AS SELECT id, test_run_id, status, is_flaky, is_new, duration, inserted_at, ran_at, name, project_id
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
          FROM test_case_runs
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
