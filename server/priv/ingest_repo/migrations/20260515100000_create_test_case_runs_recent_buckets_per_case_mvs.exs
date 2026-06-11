defmodule Tuist.IngestRepo.Migrations.CreateTestCaseRunsRecentBucketsPerCaseMvs do
  @moduledoc """
  Adds smaller rolling-window aggregates for flaky-test automations.

  `test_case_runs_recent_per_case` intentionally keeps the latest 1000 runs per
  test case because that is the user-facing `rolling_window_size` cap. Most
  automation evaluations, however, use much smaller windows. Reading the
  1000-entry aggregate for those windows forces ClickHouse to deserialize and
  merge far more state than the query can use.

  These tables keep the latest 100, 250, 500, and 750 runs as
  `groupArraySorted(N)` states keyed by `-ran_at_microseconds`. The monitor
  picks the smallest bucket that can satisfy the configured window and falls
  back to the existing 1000-entry aggregate above 750, so the max window stays
  1000 without making smaller windows pay the 1000-state cost.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @window_sizes [100, 250, 500, 750]
  @project_chunk_size 10
  @chunk_throttle_ms 100

  def up do
    migration_started_at = DateTime.utc_now()

    for window_size <- @window_sizes do
      IngestRepo.query!("DROP VIEW IF EXISTS #{mv(window_size)}")
      IngestRepo.query!("DROP TABLE IF EXISTS #{table_name(window_size)}")
      create_table(window_size)
    end

    for window_size <- @window_sizes do
      backfill_by_partition(window_size, migration_started_at)
      create_materialized_view(window_size)

      backfill_until_materialized_view_start(
        window_size,
        migration_started_at,
        DateTime.utc_now()
      )
    end
  end

  def down do
    for window_size <- @window_sizes do
      IngestRepo.query!("DROP VIEW IF EXISTS #{mv(window_size)}")
      IngestRepo.query!("DROP TABLE IF EXISTS #{table_name(window_size)}")
    end
  end

  defp create_table(window_size) do
    IngestRepo.query!("""
    CREATE TABLE #{table_name(window_size)} (
      project_id Int64,
      test_case_id UUID,
      recent_runs AggregateFunction(groupArraySorted(#{window_size}), Tuple(Int64, UInt8))
    ) ENGINE = AggregatingMergeTree
    ORDER BY (project_id, test_case_id)
    """)
  end

  defp create_materialized_view(window_size) do
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{mv(window_size)}
    TO #{table_name(window_size)}
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(is_flaky))) AS recent_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  defp backfill_by_partition(window_size, migration_started_at) do
    cutoff = DateTime.to_iso8601(migration_started_at)

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
      partition_int = String.to_integer(partition)
      project_ids = project_ids_for_partition(partition_int, cutoff)

      Logger.info(
        "Backfilling partition #{partition} into #{table_name(window_size)} " <>
          "(#{length(project_ids)} projects in #{div(length(project_ids) + @project_chunk_size - 1, @project_chunk_size)} chunk(s))"
      )

      project_ids
      |> Enum.chunk_every(@project_chunk_size)
      |> Enum.with_index(1)
      |> Enum.each(fn {chunk, idx} ->
        backfill_chunk_with_daily_fallback(window_size, partition_int, chunk, idx, cutoff)

        Process.sleep(@chunk_throttle_ms)
      end)
    end
  end

  defp project_ids_for_partition(partition, cutoff) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT project_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
          AND inserted_at < parseDateTime64BestEffort({cutoff:String}, 6)
          AND test_case_id IS NOT NULL
        ORDER BY project_id
        """,
        %{partition: partition, cutoff: cutoff},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  defp days_for_partition_chunk(partition, project_ids, cutoff) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT toString(toDate(inserted_at)) AS day
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
          AND inserted_at < parseDateTime64BestEffort({cutoff:String}, 6)
          AND project_id IN {project_ids:Array(Int64)}
          AND test_case_id IS NOT NULL
        ORDER BY day
        """,
        %{partition: partition, cutoff: cutoff, project_ids: project_ids},
        timeout: 600_000
      )

    Enum.map(rows, fn [day] -> day end)
  end

  defp backfill_chunk_with_daily_fallback(window_size, partition, project_ids, idx, cutoff) do
    backfill_chunk(window_size, partition, project_ids, idx, cutoff)
  rescue
    e in Ch.Error ->
      cond do
        memory_limit_exceeded?(e) ->
          Logger.warning(
            "Backfilling chunk #{idx} of partition #{partition} into #{table_name(window_size)} " <>
              "exceeded ClickHouse memory; retrying with day-sized chunks"
          )

          backfill_chunk_by_day(window_size, partition, project_ids, idx, cutoff)

        table_is_read_only?(e) ->
          retry_on_transient_failure(fn ->
            backfill_chunk(window_size, partition, project_ids, idx, cutoff)
          end)

        true ->
          reraise e, __STACKTRACE__
      end
  end

  defp backfill_chunk_by_day(window_size, partition, project_ids, idx, cutoff) do
    days = days_for_partition_chunk(partition, project_ids, cutoff)

    days
    |> Enum.with_index(1)
    |> Enum.each(fn {day, day_idx} ->
      backfill_day_chunk_with_project_fallback(
        window_size,
        partition,
        project_ids,
        idx,
        day,
        day_idx,
        cutoff
      )

      Process.sleep(@chunk_throttle_ms)
    end)
  end

  defp backfill_chunk(window_size, partition, project_ids, idx, cutoff) do
    Logger.debug(
      "Backfilling chunk #{idx} of partition #{partition} into #{table_name(window_size)} " <>
        "(#{length(project_ids)} projects: #{Enum.at(project_ids, 0)}..#{List.last(project_ids)})"
    )

    IngestRepo.query!(
      """
      INSERT INTO #{table_name(window_size)}
      SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(is_flaky))) AS recent_runs
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND inserted_at < parseDateTime64BestEffort({cutoff:String}, 6)
        AND project_id IN {project_ids:Array(Int64)}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = 6000000000,
        max_bytes_before_external_group_by = 2500000000
      """,
      %{partition: partition, cutoff: cutoff, project_ids: project_ids},
      timeout: 1_200_000
    )
  end

  defp backfill_day_chunk(window_size, partition, project_ids, idx, day, day_idx, cutoff) do
    day_start = "#{day} 00:00:00"
    day_end = "#{Date.add(Date.from_iso8601!(day), 1)} 00:00:00"

    Logger.debug(
      "Backfilling day chunk #{day_idx} (#{day}) for chunk #{idx} of partition #{partition} " <>
        "into #{table_name(window_size)}"
    )

    IngestRepo.query!(
      """
      INSERT INTO #{table_name(window_size)}
      SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(is_flaky))) AS recent_runs
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND inserted_at >= parseDateTime64BestEffort({day_start:String}, 6)
        AND inserted_at < parseDateTime64BestEffort({day_end:String}, 6)
        AND inserted_at < parseDateTime64BestEffort({cutoff:String}, 6)
        AND project_id IN {project_ids:Array(Int64)}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = 6000000000,
        max_bytes_before_external_group_by = 2500000000
      """,
      %{
        partition: partition,
        day_start: day_start,
        day_end: day_end,
        cutoff: cutoff,
        project_ids: project_ids
      },
      timeout: 1_200_000
    )
  end

  defp backfill_day_chunk_with_project_fallback(
         window_size,
         partition,
         project_ids,
         idx,
         day,
         day_idx,
         cutoff
       ) do
    backfill_day_chunk(window_size, partition, project_ids, idx, day, day_idx, cutoff)
  rescue
    e in Ch.Error ->
      cond do
        memory_limit_exceeded?(e) and length(project_ids) > 1 ->
          Logger.warning(
            "Backfilling day #{day} for chunk #{idx} of partition #{partition} " <>
              "into #{table_name(window_size)} exceeded ClickHouse memory; retrying per project"
          )

          project_ids
          |> Enum.each(fn project_id ->
            retry_on_transient_failure(fn ->
              backfill_day_chunk(
                window_size,
                partition,
                [project_id],
                idx,
                day,
                day_idx,
                cutoff
              )
            end)

            Process.sleep(@chunk_throttle_ms)
          end)

        table_is_read_only?(e) ->
          retry_on_transient_failure(fn ->
            backfill_day_chunk(window_size, partition, project_ids, idx, day, day_idx, cutoff)
          end)

        true ->
          reraise e, __STACKTRACE__
      end
  end

  defp backfill_until_materialized_view_start(
         window_size,
         migration_started_at,
         materialized_view_started_at
       ) do
    start_cutoff = DateTime.to_iso8601(migration_started_at)
    end_cutoff = DateTime.to_iso8601(materialized_view_started_at)

    Logger.info("Backfilling rows inserted while #{table_name(window_size)} was being built")

    retry_on_transient_failure(fn ->
      IngestRepo.query!(
        """
        INSERT INTO #{table_name(window_size)}
        SELECT
          project_id,
          assumeNotNull(test_case_id) AS test_case_id,
          groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(is_flaky))) AS recent_runs
        FROM test_case_runs
        WHERE inserted_at >= parseDateTime64BestEffort({start_cutoff:String}, 6)
          AND inserted_at < parseDateTime64BestEffort({end_cutoff:String}, 6)
          AND test_case_id IS NOT NULL
        GROUP BY project_id, test_case_id
        SETTINGS
          optimize_aggregation_in_order = 1,
          max_threads = 1,
          max_memory_usage = 6000000000,
          max_bytes_before_external_group_by = 2500000000
        """,
        %{start_cutoff: start_cutoff, end_cutoff: end_cutoff},
        timeout: 1_200_000
      )
    end)
  end

  defp table_name(window_size), do: "test_case_runs_recent_#{window_size}_per_case"
  defp mv(window_size), do: "#{table_name(window_size)}_mv"

  defp retry_on_transient_failure(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      message = to_string(e.message)

      transient? =
        table_is_read_only?(e) or
          memory_limit_exceeded?(e)

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

  defp memory_limit_exceeded?(%Ch.Error{} = error),
    do: String.contains?(to_string(error.message), "MEMORY_LIMIT_EXCEEDED")

  defp table_is_read_only?(%Ch.Error{} = error),
    do: String.contains?(to_string(error.message), "TABLE_IS_READ_ONLY")
end
