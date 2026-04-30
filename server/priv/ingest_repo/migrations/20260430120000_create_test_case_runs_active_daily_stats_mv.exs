defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsActiveDailyStatsMv do
  @moduledoc """
  Pre-aggregates `uniqExact(test_case_id)` per (project_id, date, is_ci) so the
  Test Cases analytics chart no longer scans `test_case_runs` for every bucket.

  The chart calls `Analytics.test_cases_count_analytics/2`, which evaluates a
  rolling 14-day window at every bucket endpoint. Without a pre-aggregate each
  endpoint reissues a `uniqExact(test_case_id)` over `test_case_runs`. The
  table's ORDER BY `(project_id, test_case_id, ran_at, id)` only narrows by
  `project_id`; the `ran_at` predicate forces a scan of every row for that
  project (~30 B rows / 1 TB read per hour from production telemetry).

  This MV stores `uniqExactState(test_case_id)` keyed by
  (project_id, date, is_ci). The 14-day query reads ~28 pre-aggregated rows
  via `uniqExactMerge` instead of millions of raw runs.

  Uses an explicit storage table with the MV trigger named
  `test_case_runs_active_daily_stats_mv` and a partition-by-partition
  backfill, mirroring `recreate_flaky_test_case_runs_mv` to avoid the
  ZooKeeper "table is shutting down" race on ClickHouse Cloud during a
  POPULATE.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_active_daily_stats_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_active_daily_stats")

    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_runs_active_daily_stats (
      project_id Int64,
      date Date,
      is_ci Bool,
      test_case_ids_state AggregateFunction(uniqExact, UUID)
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, date, is_ci)
    """)

    backfill_by_partition()

    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_active_daily_stats_mv
    TO test_case_runs_active_daily_stats
    AS SELECT
      project_id,
      toDate(ran_at) AS date,
      is_ci,
      uniqExactState(assumeNotNull(test_case_id)) AS test_case_ids_state
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, toDate(ran_at), is_ci
    """)
  end

  def down do
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_active_daily_stats_mv")
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_runs_active_daily_stats")
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
      Logger.info("Backfilling partition #{partition} into test_case_runs_active_daily_stats")

      retry_on_shutting_down(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_runs_active_daily_stats
          SELECT
            project_id,
            toDate(ran_at) AS date,
            is_ci,
            uniqExactState(assumeNotNull(test_case_id)) AS test_case_ids_state
          FROM test_case_runs
          WHERE toYYYYMM(inserted_at) = {partition:UInt32} AND test_case_id IS NOT NULL
          GROUP BY project_id, toDate(ran_at), is_ci
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
