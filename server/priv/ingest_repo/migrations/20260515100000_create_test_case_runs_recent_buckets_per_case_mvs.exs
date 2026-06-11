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
  @max_window_size 1000
  @project_chunk_size 25
  @chunk_throttle_ms 100

  def up do
    for window_size <- @window_sizes do
      IngestRepo.query!("DROP VIEW IF EXISTS #{mv(window_size)}")
      IngestRepo.query!("DROP TABLE IF EXISTS #{table_name(window_size)}")
      create_table(window_size)
      backfill_from_recent_per_case(window_size)
      create_materialized_view(window_size)
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

  defp backfill_from_recent_per_case(window_size) do
    project_ids = source_project_ids()

    Logger.info(
      "Backfilling #{table_name(window_size)} from test_case_runs_recent_per_case " <>
        "(#{length(project_ids)} projects in #{div(length(project_ids) + @project_chunk_size - 1, @project_chunk_size)} chunk(s))"
    )

    project_ids
    |> Enum.chunk_every(@project_chunk_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, idx} ->
      backfill_recent_per_case_chunk_with_fallback(window_size, chunk, idx)

      Process.sleep(@chunk_throttle_ms)
    end)
  end

  defp source_project_ids do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT project_id
        FROM test_case_runs_recent_per_case
        ORDER BY project_id
        """,
        %{},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  defp backfill_recent_per_case_chunk_with_fallback(window_size, project_ids, idx) do
    backfill_recent_per_case_chunk(window_size, project_ids, idx)
  rescue
    e in Ch.Error ->
      cond do
        memory_limit_exceeded?(e) and length(project_ids) > 1 ->
          Logger.warning(
            "Backfilling chunk #{idx} into #{table_name(window_size)} exceeded ClickHouse memory; " <>
              "retrying per project"
          )

          Enum.each(project_ids, fn project_id ->
            retry_on_transient_failure(fn ->
              backfill_recent_per_case_chunk(window_size, [project_id], idx)
            end)

            Process.sleep(@chunk_throttle_ms)
          end)

        table_is_read_only?(e) ->
          retry_on_transient_failure(fn ->
            backfill_recent_per_case_chunk(window_size, project_ids, idx)
          end)

        true ->
          reraise e, __STACKTRACE__
      end
  end

  defp backfill_recent_per_case_chunk(window_size, project_ids, idx) do
    Logger.debug(
      "Backfilling chunk #{idx} into #{table_name(window_size)} " <>
        "(#{length(project_ids)} projects: #{Enum.at(project_ids, 0)}..#{List.last(project_ids)})"
    )

    IngestRepo.query!(
      """
      INSERT INTO #{table_name(window_size)}
      SELECT
        project_id,
        test_case_id,
        groupArraySortedState(#{window_size})((
          -toUnixTimestamp64Micro(tupleElement(recent_run, 1)),
          toUInt8(tupleElement(recent_run, 2))
        )) AS recent_runs
      FROM (
        SELECT
          project_id,
          test_case_id,
          arrayJoin(
            arraySlice(
              arrayReverseSort(run -> tupleElement(run, 1), groupArrayLastMerge(#{@max_window_size})(recent_runs)),
              1,
              #{window_size}
            )
          ) AS recent_run
        FROM test_case_runs_recent_per_case
        WHERE project_id IN {project_ids:Array(Int64)}
        GROUP BY project_id, test_case_id
      )
      GROUP BY project_id, test_case_id
      SETTINGS
        max_threads = 1,
        max_memory_usage = 6000000000,
        max_bytes_before_external_group_by = 2500000000
      """,
      %{project_ids: project_ids},
      timeout: 1_200_000
    )
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
