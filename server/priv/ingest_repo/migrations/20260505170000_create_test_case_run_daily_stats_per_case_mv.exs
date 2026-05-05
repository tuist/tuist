defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunDailyStatsPerCaseMv do
  @moduledoc """
  Per-test-case daily aggregate of test_case_runs.

  The flaky-tests automation engine needs `count` / `countIf(is_flaky)`
  per `test_case_id` over a window for every comparison direction
  (`gte` / `gt` / `lt` / `lte`). The main `test_case_runs` table is
  ordered by `(test_run_id, …)` so a `WHERE project_id = ?` filter has
  no prefix match — the existing `flaky_test_case_runs` MV speeds up
  the `>=` / `>` direction by storing only flaky rows, but the `<` /
  `<=` direction still requires the full count of every run (flaky and
  non-flaky) to compute either rate or "no flakes in window."

  This new MV keeps a per-`(project_id, date, test_case_id)` row with
  total runs and flaky runs, so the monitor can answer all four
  comparisons via a small prefix scan keyed on the project.

  Mirrors the explicit storage-table pattern used by
  `flaky_test_case_runs` so the backfill writes directly to the
  storage table and avoids the ZooKeeper "TABLE_IS_READ_ONLY" race on
  ClickHouse Cloud.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_run_daily_stats_per_case (
      project_id Int64,
      date Date,
      test_case_id UUID,
      run_count AggregateFunction(count),
      flaky_run_count AggregateFunction(sum, UInt8)
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, date, test_case_id)
    """)

    backfill_by_partition()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_run_daily_stats_per_case_mv
    TO test_case_run_daily_stats_per_case
    AS SELECT
      project_id,
      toDate(inserted_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id,
      countState() AS run_count,
      sumState(toUInt8(is_flaky)) AS flaky_run_count
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, date, test_case_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_run_daily_stats_per_case_mv")
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_run_daily_stats_per_case")
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
      Logger.info("Backfilling partition #{partition} into test_case_run_daily_stats_per_case")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_run_daily_stats_per_case
          SELECT
            project_id,
            toDate(inserted_at) AS date,
            assumeNotNull(test_case_id) AS test_case_id,
            countState() AS run_count,
            sumState(toUInt8(is_flaky)) AS flaky_run_count
          FROM test_case_runs
          WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND test_case_id IS NOT NULL
          GROUP BY project_id, date, test_case_id
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
