defmodule Tuist.IngestRepo.Migrations.BackfillTestCaseRunsRecentWindowPerCase do
  @moduledoc """
  Seeds the packed rolling aggregate from the 100-entry tuple bucket.

  `20260817120000` created `test_case_runs_recent_window_per_case` forward-only,
  which left the monitor reading two different aggregates: the tuple bucket for
  windows it already served, and the packed one only above them. That split
  existed only because the packed table started empty.

  `test_case_runs_recent_100_per_case` already holds the latest runs per test
  case, and its two parallel tuple aggregates carry exactly the fields a packed
  entry needs. Reconstructing from it reads one row per test case rather than
  the multi-billion-row fact table, and reproduces the tuple bucket's contents
  exactly, so one aggregate can serve every window.

  ## Reconstruction

  Both materialized views read the same `test_case_runs` rows, so de-duplicating
  each aggregate to one entry per run key yields two arrays that zip in a single
  pass. Zipping by key lookup instead is quadratic, and in a vectorised engine
  that materialises `entries x keys` intermediates for the whole block: it
  allocated in 625 MiB chunks and exceeded the memory limit on its own.

  Alignment is not free, though, and assuming it is what failed this migration
  in production twice. The key sets diverge for at least three reasons, and each
  one was found only after the repair aimed at the previous one shipped:

    * `groupArraySorted` orders on the whole tuple, so the flag breaks ties on
      the run key rather than being ignored after it. A run key carrying two
      physical entries can straddle the source's 100-entry ceiling and be cut on
      different sides of it in the two aggregates.
    * `recent_successful_runs` was added later, by `20260702120000`, with its own
      backfill. Wherever that did not reproduce the older aggregate exactly, keys
      are missing from the interior rather than the tail. One test case in
      project 1000 carries 17 such keys starting at position 84 of 100, which is
      exactly the 17-entry delta the second production failure reported.
    * A test case can hold one aggregate and not the other at all, which is a
      zero-length array against a full one.

  So the arrays are restricted to the keys they share rather than repaired
  cause by cause. `arrayFilter` preserves order, so both sides come out carrying
  the same keys in the same positions and entry `i` is the same run on both,
  whatever the inputs looked like. That is correct without enumerating the
  causes, including the one nobody has found yet, and it is strictly more
  faithful than trimming: where a boundary repair drops every key above the
  smaller maximum, this drops only the keys that are genuinely unpaired.

  Cost is a membership test per entry against an array capped at 100. That is
  not the shape measured at 625 MiB chunks: that one built `entries x keys`
  intermediates for the whole block through a per-entry lookup inside
  `arrayMap`. `has` returns a scalar and allocates nothing.

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
  @target_table "test_case_runs_recent_window_per_case"
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

  # The rows this wrote are indistinguishable from the ones the materialized
  # view writes, so there is nothing to selectively remove.
  def down, do: :ok

  # Entries key on the negated run timestamp, so a run that predates the view
  # sorts above this boundary. The comparison happens against packed entries, so
  # the boundary is scaled into the same space: an entry is `run_key * 4 + flags`
  # with flags in 0..3, so `run_key * 4 + 3` excludes every flag combination of a
  # run at the boundary itself while admitting any strictly older run.
  #
  # The row count decides whether the version is recorded, not the aggregate.
  # `inserted_at` is a non-nullable `DateTime`, so `min()` over no rows returns
  # the epoch rather than NULL and the boundary computes to a positive value.
  # Every run key is negative, so that value would filter out every run and the
  # backfill would report success having written nothing.
  defp packed_view_boundary do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    %{rows: rows} =
      IngestRepo.query!(
        """
        SELECT
          count() AS recorded,
          -toUnixTimestamp64Micro(toDateTime64(min(inserted_at), 6)) * 4 + 3 AS boundary
        FROM schema_migrations
        WHERE version = {version:Int64}
        """,
        %{version: @packed_view_migration_version}
      )

    case rows do
      [[recorded, boundary]] when recorded > 0 and is_integer(boundary) ->
        boundary

      _ ->
        Logger.warning(
          "#{@packed_view_migration_version} is not recorded; backfilling every run in the source"
        )

        -System.os_time(:microsecond) * 4 + 3
    end
  end

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
              arrayFilter(entry -> has(successful_keys, tupleElement(entry, 1)), flaky_keyed),
              arrayFilter(entry -> has(flaky_keys, tupleElement(entry, 1)), successful_keyed)
            )
          )
        ) AS recent_runs
      FROM (
        SELECT
          project_id,
          test_case_id,
          flaky_keyed,
          successful_keyed,
          -- Restricting both sides to the keys they share is what makes the
          -- positional zip below sound. Filtering preserves order, and both
          -- results carry the same keys, so entry `i` is the same run on both
          -- sides whatever the inputs looked like.
          --
          -- The alternative was to reason about *why* the key sets differ and
          -- repair only that. Two causes are known: `groupArraySorted` orders
          -- on the whole tuple, so the flag breaks ties on the run key and a
          -- duplicated key straddling the source's 100-entry ceiling is cut on
          -- different sides in the two aggregates; and
          -- `recent_successful_runs` was added later, by `20260702120000`,
          -- with its own backfill, so wherever that did not reproduce the
          -- older aggregate exactly, keys are missing from the interior rather
          -- than the tail. A boundary repair addresses the first and not the
          -- second, which is how this migration failed twice. Intersecting is
          -- correct without knowing the cause, including one nobody has found
          -- yet.
          --
          -- The cost is a membership test per entry against an array capped at
          -- 100. That is not the shape the earlier attempt measured at 625 MiB
          -- chunks: that one built `entries x keys` intermediates for the whole
          -- block through a per-entry lookup inside `arrayMap`. `has` returns a
          -- scalar, so this adds two filtered copies rather than a cross
          -- product. It is not free, though, and the budget is shared with the
          -- reader and the `FINAL` merge, which is why `max_block_size` below
          -- is what bounds all three.
          arrayMap(entry -> tupleElement(entry, 1), flaky_keyed) AS flaky_keys,
          arrayMap(entry -> tupleElement(entry, 1), successful_keyed) AS successful_keys
        FROM (
          SELECT
            project_id,
            test_case_id,
            arrayFilter(
              (entry, next_entry) -> tupleElement(entry, 1) != tupleElement(next_entry, 1),
              flaky_runs,
              arrayShiftLeft(flaky_runs, 1, #{@flag_sentinel})
            ) AS flaky_keyed,
            arrayFilter(
              (entry, next_entry) -> tupleElement(entry, 1) != tupleElement(next_entry, 1),
              successful_runs,
              arrayShiftLeft(successful_runs, 1, #{@flag_sentinel})
            ) AS successful_keyed
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
        )
      )
      SETTINGS
        max_threads = 2,
        -- 4096 overran the budget below on the first project whose parts are
        -- large enough to matter: 1.87 GiB wanted against 1.86 GiB allowed,
        -- reported once from the part reader (`max_rows_to_read = 4096`, which
        -- is this setting) and once from the `FINAL` merge, so it is the whole
        -- query rather than one operator. Rows in flight scale this directly,
        -- and the ceiling is shared with live traffic, so it is cheaper to read
        -- narrower than to claim more of the 8 GiB the environment budgets for
        -- every Tuist query together.
        max_block_size = 1024,
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
