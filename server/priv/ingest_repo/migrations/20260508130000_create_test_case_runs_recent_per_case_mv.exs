defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsRecentPerCaseMv do
  @moduledoc """
  Per-test-case rolling-window aggregate of `test_case_runs`.

  The flaky-tests automation engine's "rolling window" mode evaluates the last
  N runs per `(project_id, test_case_id)` ordered by `ran_at`. Reading raw
  `test_case_runs` for that pattern scans every run in the project's lookback
  range — measured at 200M+ rows for 30 days on busy projects, with no primary
  key prefix that fits "last N per test case per project."

  This MV maintains a `groupArrayLast(N)` aggregate of `(ran_at, is_flaky)`
  tuples per test case, capped at 1000 entries to match the changeset's
  `rolling_window_size` cap. A project's whole rolling-window scan becomes
  one row per test case — bounded by `active_test_cases`, regardless of run
  volume.

  Mirrors the `test_case_run_daily_stats_per_case` pattern (explicit storage
  table + MV trigger + partition-by-partition backfill) so it survives the
  ClickHouse Cloud `TABLE_IS_READ_ONLY` race during compaction churn.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @max_window_size 1000

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_recent_per_case (
      project_id Int64,
      test_case_id UUID,
      recent_runs AggregateFunction(groupArrayLast(#{@max_window_size}), Tuple(DateTime64(6), UInt8))
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, test_case_id)
    """)

    backfill_by_partition()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_recent_per_case_mv
    TO test_case_runs_recent_per_case
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArrayLastState(#{@max_window_size})((ran_at, toUInt8(is_flaky))) AS recent_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_recent_per_case_mv")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_recent_per_case")
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_recent_per_case")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_runs_recent_per_case
          SELECT
            project_id,
            assumeNotNull(test_case_id) AS test_case_id,
            groupArrayLastState(#{@max_window_size})((ran_at, toUInt8(is_flaky))) AS recent_runs
          FROM test_case_runs
          WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND test_case_id IS NOT NULL
          GROUP BY project_id, test_case_id
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
