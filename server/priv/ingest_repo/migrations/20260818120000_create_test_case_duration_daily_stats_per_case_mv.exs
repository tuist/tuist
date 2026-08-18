defmodule Tuist.IngestRepo.Migrations.CreateTestCaseDurationDailyStatsPerCaseMv do
  @moduledoc """
  Per-test-case daily duration aggregates, split by environment.

  The Test Cases listing showed `test_cases.avg_duration`, a denormalized
  arithmetic mean of the last 50 runs written at ingestion. It has no time
  bound, no environment split, and no outlier resistance: a single paused
  debugger on a local run inflated one production test case to a 10-minute
  "average" against a 978 ms median, and that number both displayed and
  ranked the row.

  This table gives the listing per-test-case quantile and average states so it
  can show and sort by a real statistic over a bounded window, and can answer
  "how long does this take on CI" separately from "how long does this take
  locally".

  The sort key leads with `test_case_id` rather than `date` because the only
  read is "every test case in this project, over the trailing window": grouping
  by `test_case_id` is then in sorted order, so ClickHouse streams one group at
  a time instead of holding a quantile state per test case in memory for the
  whole aggregation. Monthly partitioning keeps the window filter cheap without
  putting `date` in front. `is_ci` is in the key, not merely a column, so the
  CI/Local dropdown narrows the read rather than filtering after the fact.

  This is a new table rather than new columns on
  `test_case_run_daily_stats_per_case` because adding `is_ci` to that table's
  sort key would change its aggregation grain: every existing row would
  silently claim `is_ci = false`, and the flaky/reliability automations that
  read its count states would start seeing counts and durations keyed on
  different grains in one table.

  `date` is derived from `ran_at`, matching `test_case_runs_active_daily_stats`
  and the listing's own active window, so the durations shown cover the same
  runs the window admits.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @project_chunk_size 1
  @chunk_throttle_ms 250

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE IF NOT EXISTS test_case_duration_daily_stats_per_case (
      project_id Int64,
      date Date,
      test_case_id UUID,
      is_ci Bool,
      run_count AggregateFunction(count),
      avg_duration AggregateFunction(avg, Int32),
      p50_duration AggregateFunction(quantile(0.5), Int32),
      p90_duration AggregateFunction(quantile(0.9), Int32),
      p99_duration AggregateFunction(quantile(0.99), Int32)
    ) ENGINE = AggregatingMergeTree
    PARTITION BY toYYYYMM(date)
    ORDER BY (project_id, test_case_id, date, is_ci)
    """)

    backfill_by_partition()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_duration_daily_stats_per_case_mv
    TO test_case_duration_daily_stats_per_case
    AS SELECT
      project_id,
      toDate(ran_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id,
      is_ci,
      countState() AS run_count,
      avgState(duration) AS avg_duration,
      quantileState(0.5)(duration) AS p50_duration,
      quantileState(0.9)(duration) AS p90_duration,
      quantileState(0.99)(duration) AS p99_duration
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, date, test_case_id, is_ci
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_duration_daily_stats_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_duration_daily_stats_per_case")
  end

  # Newest partition first. The listing only reads a trailing two-week window,
  # so the feature is correct as soon as the current partition lands; an older
  # partition that needs several retries delays nothing user-visible.
  defp backfill_by_partition do
    {:ok, %{rows: partitions}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
        ORDER BY partition DESC
        """,
        %{table: "test_case_runs"}
      )

    for [partition] <- partitions do
      partition_int = String.to_integer(partition)
      project_ids = project_ids_for_partition(partition_int)

      Logger.info(
        "Backfilling partition #{partition} into test_case_duration_daily_stats_per_case " <>
          "(#{length(project_ids)} projects)"
      )

      project_ids
      |> Enum.chunk_every(@project_chunk_size)
      |> Enum.each(fn chunk ->
        retry_on_transient_failure(fn -> backfill_chunk(partition_int, chunk) end)
        Process.sleep(@chunk_throttle_ms)
      end)
    end
  end

  defp project_ids_for_partition(partition) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT project_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        ORDER BY project_id
        """,
        %{partition: partition},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  # `toYYYYMM(inserted_at)` selects the source partition while `date` groups on
  # `ran_at`. Runs whose execution and ingestion fall on opposite sides of a
  # month boundary are therefore written from the partition that holds them,
  # into the destination partition their `ran_at` belongs to, so no run is
  # visited twice and none is skipped.
  #
  # The memory ceiling is deliberately generous: an earlier backfill against
  # the sibling per-case table died at ~3.74 GiB on the heaviest partition
  # chunk, and quantile states are larger than the count states it was writing.
  defp backfill_chunk(partition, project_ids) do
    IngestRepo.query!(
      """
      INSERT INTO test_case_duration_daily_stats_per_case
        (project_id, date, test_case_id, is_ci, run_count, avg_duration,
         p50_duration, p90_duration, p99_duration)
      SELECT
        project_id,
        toDate(ran_at) AS date,
        assumeNotNull(test_case_id) AS test_case_id,
        is_ci,
        countState() AS run_count,
        avgState(duration) AS avg_duration,
        quantileState(0.5)(duration) AS p50_duration,
        quantileState(0.9)(duration) AS p90_duration,
        quantileState(0.99)(duration) AS p99_duration
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND project_id IN {project_ids:Array(Int64)}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, date, test_case_id, is_ci
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = 12000000000,
        max_bytes_before_external_group_by = 5000000000
      """,
      %{partition: partition, project_ids: project_ids},
      timeout: 1_200_000
    )
  end

  defp retry_on_transient_failure(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      message = to_string(e.message)

      transient? =
        String.contains?(message, "TABLE_IS_READ_ONLY") or
          String.contains?(message, "MEMORY_LIMIT_EXCEEDED")

      if attempts > 1 and transient? do
        Logger.warning(
          "ClickHouse returned a transient error (#{String.slice(message, 0, 80)}...); " <>
            "retrying in 5s (#{attempts - 1} attempts left)"
        )

        Process.sleep(:timer.seconds(5))
        retry_on_transient_failure(fun, attempts - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
