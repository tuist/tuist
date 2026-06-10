defmodule Tuist.IngestRepo.Migrations.AddReliabilityAggregatesToTestCaseRunStats do
  @moduledoc """
  Adds per-test-case success aggregates for reliability-rate automations.

  The existing flakiness automations use daily and rolling aggregate tables so
  scheduled evaluations scan bounded per-test-case state instead of raw
  `test_case_runs`. Reliability needs the same shape, but it measures
  successful runs over total runs.

  The migration is additive: existing materialized views continue to populate
  run/flaky states, and the new views populate only the successful-run states
  into the same storage tables.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @max_window_size 1000
  @project_chunk_size 1
  @chunk_throttle_ms 250

  def up do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    ALTER TABLE test_case_run_daily_stats_per_case
    ADD COLUMN IF NOT EXISTS successful_run_count AggregateFunction(sum, UInt8)
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    ALTER TABLE test_case_runs_recent_per_case
    ADD COLUMN IF NOT EXISTS recent_successful_runs AggregateFunction(groupArrayLast(#{@max_window_size}), Tuple(DateTime64(6), UInt8))
    """)

    backfill_daily_by_partition()
    backfill_recent_by_partition()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_run_daily_success_stats_per_case_mv
    TO test_case_run_daily_stats_per_case
    AS SELECT
      project_id,
      toDate(inserted_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id,
      sumState(toUInt8(status = 'success')) AS successful_run_count
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, date, test_case_id
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS test_case_runs_recent_success_per_case_mv
    TO test_case_runs_recent_per_case
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArrayLastState(#{@max_window_size})((ran_at, toUInt8(status = 'success'))) AS recent_successful_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  def down do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_runs_recent_success_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_run_daily_success_stats_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    ALTER TABLE test_case_runs_recent_per_case
    DROP COLUMN IF EXISTS recent_successful_runs
    """)

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    ALTER TABLE test_case_run_daily_stats_per_case
    DROP COLUMN IF EXISTS successful_run_count
    """)
  end

  defp backfill_daily_by_partition do
    {:ok, %{rows: partitions}} = active_partitions()

    for [partition] <- partitions do
      Logger.info(
        "Backfilling partition #{partition} into test_case_run_daily_stats_per_case successful_run_count"
      )

      retry_on_transient_failure(fn ->
        IngestRepo.query!(
          """
          INSERT INTO test_case_run_daily_stats_per_case
            (project_id, date, test_case_id, successful_run_count)
          SELECT
            project_id,
            toDate(inserted_at) AS date,
            assumeNotNull(test_case_id) AS test_case_id,
            sumState(toUInt8(status = 'success')) AS successful_run_count
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

  defp backfill_recent_by_partition do
    {:ok, %{rows: partitions}} = active_partitions()

    for [partition] <- partitions do
      partition_int = String.to_integer(partition)
      project_ids = project_ids_for_partition(partition_int)

      Logger.info(
        "Backfilling partition #{partition} into test_case_runs_recent_per_case recent_successful_runs " <>
          "(#{length(project_ids)} projects in #{div(length(project_ids) + @project_chunk_size - 1, @project_chunk_size)} chunk(s))"
      )

      project_ids
      |> Enum.chunk_every(@project_chunk_size)
      |> Enum.with_index(1)
      |> Enum.each(fn {chunk, idx} ->
        retry_on_transient_failure(fn ->
          backfill_recent_chunk(partition_int, chunk, idx)
        end)

        Process.sleep(@chunk_throttle_ms)
      end)
    end
  end

  defp active_partitions do
    IngestRepo.query(
      """
      SELECT DISTINCT partition
      FROM system.parts
      WHERE database = currentDatabase() AND table = {table:String} AND active
      ORDER BY partition
      """,
      %{table: "test_case_runs"}
    )
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

  defp backfill_recent_chunk(partition, project_ids, idx) do
    Logger.debug(
      "Backfilling reliability chunk #{idx} of partition #{partition} " <>
        "(#{length(project_ids)} projects: #{Enum.at(project_ids, 0)}..#{List.last(project_ids)})"
    )

    IngestRepo.query!(
      """
      INSERT INTO test_case_runs_recent_per_case
        (project_id, test_case_id, recent_successful_runs)
      SELECT
        project_id,
        assumeNotNull(test_case_id) AS test_case_id,
        groupArrayLastState(#{@max_window_size})((ran_at, toUInt8(status = 'success'))) AS recent_successful_runs
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND project_id IN {project_ids:Array(Int64)}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, test_case_id
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
