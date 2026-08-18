defmodule Tuist.IngestRepo.Migrations.BackfillTestCaseRunsRecentPackedPerCase do
  @moduledoc """
  Seeds the packed rolling aggregate from the 100-entry tuple bucket.

  `20260817120000` created `test_case_runs_recent_packed_per_case` forward-only,
  which left the monitor reading two different aggregates: the tuple bucket for
  windows it already served, and the packed one only above them. That split
  existed purely because the packed table started empty.

  `test_case_runs_recent_100_per_case` already holds the latest runs per test
  case, and its two parallel tuple aggregates carry exactly the fields the
  packed entry needs. Reconstructing from it is a scan of one row per test case
  rather than of the multi-billion-row fact table, and it reproduces the tuple
  bucket's own contents exactly, so both window ranges can be served from one
  aggregate.

  The reconstruction zips the flaky and success aggregates on the run key they
  share. Both materialized views read the same `test_case_runs` rows, so both
  hold the same set of `-ran_at_micros` keys per test case; for each key the
  largest flag in each aggregate wins, which is the same collapse the reader
  applies to correction rows at query time.

  Depth is inherited, not extended. The source holds 100 physical entries, so a
  logical run that was re-inserted to set `is_flaky` consumes two of them and a
  test case recovers between 50 and 100 distinct runs. That is what the tuple
  bucket itself could serve, so windows up to its ceiling are unaffected, and
  larger windows keep filling forward until they hold a complete window.

  Chunking is per project and not optional. Merging the source's tuple states is
  the expensive half: it costs roughly 273 MiB per 2,500 test cases, so a
  whole-table pass allocates in the gigabytes and trips the memory limit, which
  is how earlier backfills of this table family failed. Each chunk falls back to
  single projects when it exceeds memory, mirroring `20260515100000`.

  Re-running is safe. A run already carried forward by the live materialized
  view is reinserted with an identical packed value, and the reader collapses
  entries that share a run key.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @source_table "test_case_runs_recent_100_per_case"
  @target_table "test_case_runs_recent_packed_per_case"
  @source_bucket_size 100
  @target_bucket_size 2000
  @project_chunk_size 10
  @chunk_throttle_ms 100

  def up do
    project_ids = source_project_ids()

    Logger.info(
      "Backfilling #{@target_table} from #{@source_table} " <>
        "(#{length(project_ids)} projects in #{div(length(project_ids) + @project_chunk_size - 1, @project_chunk_size)} chunk(s))"
    )

    project_ids
    |> Enum.chunk_every(@project_chunk_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, index} ->
      backfill_chunk_with_fallback(chunk, index)
      Process.sleep(@chunk_throttle_ms)
    end)
  end

  # The packed rows this wrote are indistinguishable from the ones the
  # materialized view writes, so there is nothing to selectively remove.
  def down, do: :ok

  defp source_project_ids do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT DISTINCT project_id
        FROM #{@source_table}
        ORDER BY project_id
        """,
        %{},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  defp backfill_chunk_with_fallback(project_ids, index) do
    backfill_chunk(project_ids, index)
  rescue
    e in Ch.Error ->
      cond do
        memory_limit_exceeded?(e) and length(project_ids) > 1 ->
          Logger.warning(
            "Backfilling chunk #{index} into #{@target_table} exceeded ClickHouse memory; retrying per project"
          )

          Enum.each(project_ids, fn project_id ->
            retry_on_transient_failure(fn -> backfill_chunk([project_id], index) end)
            Process.sleep(@chunk_throttle_ms)
          end)

        table_is_read_only?(e) ->
          retry_on_transient_failure(fn -> backfill_chunk(project_ids, index) end)

        true ->
          reraise e, __STACKTRACE__
      end
  end

  # `arrayReduce` builds the target state per row, so the only aggregation is the
  # source-state merge. Re-grouping the expanded entries instead would hold a
  # #{@target_bucket_size}-capacity state per test case for the whole chunk.
  defp backfill_chunk(project_ids, index) do
    Logger.debug(
      "Backfilling chunk #{index} into #{@target_table} " <>
        "(#{length(project_ids)} projects: #{Enum.at(project_ids, 0)}..#{List.last(project_ids)})"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!(
      """
      INSERT INTO #{@target_table} (project_id, test_case_id, recent_runs)
      SELECT
        project_id,
        test_case_id,
        arrayReduce(
          'groupArraySortedState(#{@target_bucket_size})',
          arrayMap(
            run_key ->
              run_key * 4
              + toInt64(arrayMax(arrayMap(entry -> if(tupleElement(entry, 1) = run_key, tupleElement(entry, 2), toUInt8(0)), flaky_runs))) * 2
              + toInt64(arrayMax(arrayMap(entry -> if(tupleElement(entry, 1) = run_key, tupleElement(entry, 2), toUInt8(0)), successful_runs))),
            arrayDistinct(arrayMap(entry -> tupleElement(entry, 1), flaky_runs))
          )
        ) AS recent_runs
      FROM (
        SELECT
          project_id,
          test_case_id,
          groupArraySortedMerge(#{@source_bucket_size})(recent_runs) AS flaky_runs,
          groupArraySortedMerge(#{@source_bucket_size})(recent_successful_runs) AS successful_runs
        FROM #{@source_table}
        WHERE project_id IN {project_ids:Array(Int64)}
        GROUP BY project_id, test_case_id
      )
      SETTINGS
        max_threads = 1,
        max_memory_usage = 6000000000
      """,
      %{project_ids: project_ids},
      timeout: 1_200_000
    )
  end

  defp retry_on_transient_failure(fun, attempts \\ 5) do
    fun.()
  rescue
    e in Ch.Error ->
      transient? = table_is_read_only?(e) or memory_limit_exceeded?(e)

      if attempts > 1 and transient? do
        Logger.warning(
          "ClickHouse returned a transient error (#{e.message |> to_string() |> String.slice(0, 80)}...); " <>
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
