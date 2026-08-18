defmodule Tuist.IngestRepo.Migrations.BackfillTestCaseRunsRecentPackedPerCase do
  @moduledoc """
  Seeds the packed rolling aggregate from the 100-entry tuple bucket.

  `20260817120000` created `test_case_runs_recent_packed_per_case` forward-only,
  which left the monitor reading two different aggregates: the tuple bucket for
  windows it already served, and the packed one only above them. That split
  existed only because the packed table started empty.

  `test_case_runs_recent_100_per_case` already holds the latest runs per test
  case, and its two parallel tuple aggregates carry exactly the fields a packed
  entry needs. Reconstructing from it reads one row per test case rather than
  the multi-billion-row fact table, and reproduces the tuple bucket's contents
  exactly, so one aggregate can serve every window.

  ## Reconstruction

  Both materialized views read the same `test_case_runs` rows, and
  `groupArraySorted` truncates on the sort key before the flag, so both
  aggregates always retain the same run keys per test case. De-duplicating each
  to one entry per key therefore yields two arrays aligned element for element,
  which zip in a single pass. Zipping by key lookup instead is quadratic, and in
  a vectorised engine that materialises `entries x keys` intermediates for the
  whole block: it allocated in 625 MiB chunks and exceeded the memory limit on
  its own.

  Depth is inherited, not extended. The source holds 100 physical entries, so a
  logical run re-inserted to set `is_flaky` consumes two of them and a test case
  recovers between 50 and 100 distinct runs. That is what the tuple bucket could
  serve, so windows up to its ceiling are unaffected and larger ones keep
  filling forward. The reconstructed window is a prefix of the true window.

  ## Memory

  `FINAL` plus `finalizeAggregation` keeps this a streaming row transform with
  no aggregation, so memory follows block size rather than the number of test
  cases in the query. Merging the source states with `GROUP BY` instead costs
  roughly 109 KiB per test case, which the largest project would turn into tens
  of gigabytes -- the shape that failed earlier backfills of this table family.

  What remains is a per-row component of about 5.7 KiB, so chunks are sized by
  test-case count instead of by project. `test_case_id` is derived from an MD5
  digest, so splitting the identifier space into equal ranges splits a project
  evenly, and each range stays a contiguous prefix scan of the
  `(project_id, test_case_id)` sort key.

  ## Overlap with the live view

  The materialized view has been carrying runs forward since `20260817120000`
  created it, so the newest part of the source overlaps what the target already
  holds. Reinserting those runs stays correct -- the reader collapses entries
  that share a run key -- but each one would occupy a slot twice, weakening the
  headroom the bucket is sized for. Runs are therefore bounded to those that ran
  before that migration recorded itself in `schema_migrations`, which is the
  point from which the view has been writing and is read per environment rather
  than assumed.

  The bound is on when a run executed, while the view captures a run when it is
  inserted, so a run back-dated across the boundary can still be written twice.
  A flaky correction is exactly that shape. Erring in this direction only costs
  a slot for corrections that landed during the deploy, where the opposite error
  would drop runs the view never captured.

  Re-running is safe for the same reason: a run reinserted with an identical
  packed value collapses on read.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @packed_view_migration_version 20_260_817_120_000
  @source_table "test_case_runs_recent_100_per_case"
  @target_table "test_case_runs_recent_packed_per_case"
  @target_bucket_size 2000
  @test_cases_per_chunk 25_000
  @chunk_throttle_ms 100
  @flag_sentinel "(toInt64(9223372036854775807), toUInt8(0))"

  def up do
    project_ids = source_project_ids()
    packed_view_boundary = packed_view_boundary()

    Logger.info(
      "Backfilling #{@target_table} from #{@source_table} (#{length(project_ids)} projects)"
    )

    Enum.each(project_ids, fn project_id ->
      project_id
      |> test_case_id_ranges()
      |> Enum.each(fn range ->
        retry_on_transient_failure(fn ->
          backfill_range(project_id, range, packed_view_boundary)
        end)

        Process.sleep(@chunk_throttle_ms)
      end)
    end)
  end

  # Entries key on the negated run timestamp, so a run that predates the view
  # sorts above this boundary. The comparison happens against packed entries, so
  # the boundary is scaled into the same space: an entry is `run_key * 4 + flags`
  # with flags in 0..3, so `run_key * 4 + 3` excludes every flag combination of a
  # run at the boundary itself while admitting any strictly older run. Falling
  # back to the current time backfills everything, which is what a target with no
  # view writes yet needs.
  defp packed_view_boundary do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT -toUnixTimestamp64Micro(toDateTime64(min(inserted_at), 6)) * 4 + 3
        FROM schema_migrations
        WHERE version = {version:Int64}
        """,
        %{version: @packed_view_migration_version}
      )

    case rows do
      [[boundary]] when is_integer(boundary) ->
        boundary

      _ ->
        Logger.warning(
          "#{@packed_view_migration_version} is not recorded; backfilling every run in the source"
        )

        -System.os_time(:microsecond) * 4 + 3
    end
  end

  # The rows this wrote are indistinguishable from the ones the materialized
  # view writes, so there is nothing to selectively remove.
  def down, do: :ok

  defp source_project_ids do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!(
        "SELECT DISTINCT project_id FROM #{@source_table} ORDER BY project_id",
        %{},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  # Physical row count over-counts a test case whose state still spans parts,
  # which only ever splits the work further.
  defp test_case_id_ranges(project_id) do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: [[test_case_count]]} =
      IngestRepo.query!(
        "SELECT count() FROM #{@source_table} WHERE project_id = {project_id:Int64}",
        %{project_id: project_id},
        timeout: 600_000
      )

    chunks = max(1, ceil(test_case_count / @test_cases_per_chunk))

    if chunks > 1 do
      Logger.info(
        "Splitting project #{project_id} (#{test_case_count} rows) into #{chunks} ranges"
      )
    end

    bounds = Enum.map(0..chunks, &identifier_bound(&1, chunks))

    bounds
    |> Enum.zip(tl(bounds))
    |> Enum.with_index()
    |> Enum.map(fn {{lower, upper}, index} ->
      # The final range stays open so the last identifier is always covered.
      if index == chunks - 1, do: {lower, nil}, else: {lower, upper}
    end)
  end

  defp identifier_bound(index, chunks) do
    <<div(index * Bitwise.bsl(1, 128), chunks)::128>> |> binary_part(0, 16) |> Ecto.UUID.load!()
  end

  defp backfill_range(project_id, {lower, upper}, packed_view_boundary) do
    params = %{project_id: project_id, lower: lower, boundary: packed_view_boundary}

    {upper_clause, params} =
      case upper do
        nil -> {"", params}
        _ -> {"AND test_case_id < {upper:UUID}", Map.put(params, :upper, upper)}
      end

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!(
      """
      INSERT INTO #{@target_table} (project_id, test_case_id, recent_runs)
      SELECT
        project_id,
        test_case_id,
        arrayReduce(
          'groupArraySortedState(#{@target_bucket_size})',
          arrayFilter(
            entry -> entry > {boundary:Int64},
            arrayMap(
              (flaky_entry, successful_entry) ->
                tupleElement(flaky_entry, 1) * 4
                + toInt64(tupleElement(flaky_entry, 2)) * 2
                + toInt64(tupleElement(successful_entry, 2)),
              arrayFilter(
                (entry, next_entry) -> tupleElement(entry, 1) != tupleElement(next_entry, 1),
                flaky_runs,
                arrayShiftLeft(flaky_runs, 1, #{@flag_sentinel})
              ),
              arrayFilter(
                (entry, next_entry) -> tupleElement(entry, 1) != tupleElement(next_entry, 1),
                successful_runs,
                arrayShiftLeft(successful_runs, 1, #{@flag_sentinel})
              )
            )
          )
        ) AS recent_runs
      FROM (
        SELECT
          project_id,
          test_case_id,
          finalizeAggregation(recent_runs) AS flaky_runs,
          finalizeAggregation(recent_successful_runs) AS successful_runs
        FROM #{@source_table} FINAL
        WHERE project_id = {project_id:Int64}
          AND test_case_id >= {lower:UUID}
          #{upper_clause}
      )
      SETTINGS
        max_threads = 2,
        max_block_size = 4096,
        max_memory_usage = 2000000000
      """,
      params,
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
