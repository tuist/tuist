defmodule Tuist.IngestRepo.Migrations.AddReliabilityAggregatesToRecentBucketMvs do
  @moduledoc """
  Adds per-test-case success aggregates to the bucketed rolling-window tables.

  `20260609121000` gave reliability-rate automations a `recent_successful_runs`
  aggregate, but only on the 1000-entry `test_case_runs_recent_per_case` table.
  Every reliability evaluation therefore had to `groupArrayLastMerge(1000)` and
  `arrayReverseSort` the full 1000-run state per test case — even for the default
  100-run window. That is a multi-GiB per-query cost; run concurrently across a
  busy project's active test cases it drove ClickHouse past its process memory
  ceiling and killed unrelated queries with `MEMORY_LIMIT_EXCEEDED`.

  Flakiness and flaky-run-count automations already avoid that by reading the
  smaller `test_case_runs_recent_{100,250,500,750}_per_case` buckets, which hold
  pre-sorted `groupArraySorted(N)` states (latest-first, no re-sort). This
  migration adds a parallel `recent_successful_runs` bucket aggregate to those
  same tables so reliability can take the identical fast path.

  Additive and mirrors the established bucket pattern (`20260515100000`) plus the
  success-aggregate pattern (`20260609121000`): `ALTER TABLE ... ADD COLUMN`,
  partition-chunked backfill of the historical buckets from the existing
  1000-entry aggregate, then an always-on MV per bucket. The larger buckets
  (500, 750) are populated forward-only by their MV, matching how the flakiness
  bucket migration handled them.
  """
  use Ecto.Migration
  alias Tuist.IngestRepo
  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @window_sizes [100, 250, 500, 750]
  @historical_backfill_window_sizes [100, 250]
  @max_window_size 1000
  @project_chunk_size 25
  @chunk_throttle_ms 100

  def up do
    for window_size <- @window_sizes do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("DROP VIEW IF EXISTS #{success_mv(window_size)}")

      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("""
      ALTER TABLE #{table_name(window_size)}
      ADD COLUMN IF NOT EXISTS recent_successful_runs AggregateFunction(groupArraySorted(#{window_size}), Tuple(Int64, UInt8))
      """)

      if window_size in @historical_backfill_window_sizes do
        backfill_from_recent_per_case(window_size)
      else
        Logger.info(
          "Skipping historical reliability backfill for #{table_name(window_size)}; " <>
            "the materialized view will populate it with new test case runs"
        )
      end

      create_success_materialized_view(window_size)
    end
  end

  def down do
    for window_size <- @window_sizes do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("DROP VIEW IF EXISTS #{success_mv(window_size)}")

      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      IngestRepo.query!("""
      ALTER TABLE #{table_name(window_size)}
      DROP COLUMN IF EXISTS recent_successful_runs
      """)
    end
  end

  # Mirrors the flakiness bucket MV but records `status = 'success'` instead of
  # `is_flaky`. Writing only `recent_successful_runs` leaves `recent_runs` at its
  # empty-state default; the AggregatingMergeTree merges the two per-column MV
  # streams by `(project_id, test_case_id)`, exactly as the full
  # `test_case_runs_recent_per_case` table already does with its two MVs.
  defp create_success_materialized_view(window_size) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW IF NOT EXISTS #{success_mv(window_size)}
    TO #{table_name(window_size)}
    AS SELECT
      project_id,
      assumeNotNull(test_case_id) AS test_case_id,
      groupArraySortedState(#{window_size})((-toUnixTimestamp64Micro(ran_at), toUInt8(status = 'success'))) AS recent_successful_runs
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, test_case_id
    """)
  end

  defp backfill_from_recent_per_case(window_size) do
    project_ids = source_project_ids()

    Logger.info(
      "Backfilling #{table_name(window_size)} recent_successful_runs from test_case_runs_recent_per_case " <>
        "(#{length(project_ids)} projects in #{div(length(project_ids) + @project_chunk_size - 1, @project_chunk_size)} chunk(s))"
    )

    project_ids
    |> Enum.chunk_every(@project_chunk_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, idx} ->
      backfill_chunk_with_fallback(window_size, chunk, idx)
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

  defp backfill_chunk_with_fallback(window_size, project_ids, idx) do
    backfill_chunk(window_size, project_ids, idx)
  rescue
    e in Ch.Error ->
      cond do
        memory_limit_exceeded?(e) and length(project_ids) > 1 ->
          Logger.warning(
            "Backfilling reliability chunk #{idx} into #{table_name(window_size)} exceeded ClickHouse memory; " <>
              "retrying per project"
          )

          Enum.each(project_ids, fn project_id ->
            retry_on_transient_failure(fn ->
              backfill_chunk(window_size, [project_id], idx)
            end)

            Process.sleep(@chunk_throttle_ms)
          end)

        table_is_read_only?(e) ->
          retry_on_transient_failure(fn ->
            backfill_chunk(window_size, project_ids, idx)
          end)

        true ->
          reraise e, __STACKTRACE__
      end
  end

  # Rebuilds the bucket's success state from the already-maintained 1000-entry
  # `recent_successful_runs` aggregate rather than rescanning raw
  # `test_case_runs`: take the latest N successful-run tuples, re-key them by
  # `-ran_at_microseconds`, and fold into the bucket's `groupArraySorted(N)`
  # shape. Same `(project_id IN ...)` chunking, single ordered thread, and
  # per-INSERT memory ceiling as the flakiness bucket backfill.
  defp backfill_chunk(window_size, project_ids, idx) do
    Logger.debug(
      "Backfilling reliability chunk #{idx} into #{table_name(window_size)} " <>
        "(#{length(project_ids)} projects: #{Enum.at(project_ids, 0)}..#{List.last(project_ids)})"
    )

    IngestRepo.query!(
      """
      INSERT INTO #{table_name(window_size)}
        (project_id, test_case_id, recent_successful_runs)
      SELECT
        project_id,
        test_case_id,
        groupArraySortedState(#{window_size})((
          -toUnixTimestamp64Micro(tupleElement(recent_run, 1)),
          toUInt8(tupleElement(recent_run, 2))
        )) AS recent_successful_runs
      FROM (
        SELECT
          project_id,
          test_case_id,
          arrayJoin(
            arraySlice(
              arrayReverseSort(run -> tupleElement(run, 1), groupArrayLastMerge(#{@max_window_size})(recent_successful_runs)),
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
  defp success_mv(window_size), do: "test_case_runs_recent_#{window_size}_success_per_case_mv"

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
