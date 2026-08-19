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

  ## Counting runs once

  `test_case_runs` is a `ReplacingMergeTree(inserted_at)`, and flaky-state
  corrections re-insert a whole run row with a fresh `inserted_at`
  (`Tuist.Tests.apply_test_case_run_flaky_corrections/1`). A materialized view
  fires per insert, so a corrected run reaches this table twice.

  `run_count` is therefore `uniqExactState(id)` rather than `countState()`. A
  correction changes neither `id` nor `ran_at` nor the environment, so both
  versions land in the same `(project_id, date, test_case_id, is_ci)` group and
  collapse to one. That keeps the listing's minimum-sample floor exact, which
  matters because the floor decides whether a row is shown and ranked at all: a
  count that drifted upward would let three real runs plus two corrections pass
  for five.

  The value states are not idempotent in the same way. A corrected run
  contributes its duration twice to `avgState` and to the quantile reservoirs.
  Every value in the distribution is still a duration that was really observed,
  and a correction cannot change one (it rewrites `is_flaky` only), so the
  effect is a weighting bias toward corrected runs rather than an invented
  number. Removing it needs a per-run deduplicated source, which every other
  aggregate over this table would want too and which does not belong in this
  migration.

  ## Starting from an empty table

  `up/0` drops the table and the view before creating them. This runs as a helm
  `pre-upgrade` hook whose Job retries, and a failed attempt leaves behind
  whatever ranges it had already inserted; a plain `IF NOT EXISTS` would then
  add a second copy of every one of them on the next attempt. `run_count`
  survives that (`uniqExact` over run ids collapses the copies) but the average
  and the quantile reservoirs do not: they would weight the re-inserted runs
  once per attempt. Dropping first makes every attempt start from the same
  empty table, so the states describe each run exactly as many times as the
  source holds it.

  ## What the backfill covers

  The backfill seeds a trailing `@backfill_window_days` window rather than
  every partition of `test_case_runs`. `Tuist.Tests.list_test_cases/3` is the
  only reader, it filters `date >= today - Tuist.Tests.active_window_days/0`,
  and it deliberately exposes no date-window option, so no query can reach a
  row older than that window. Seeding all history therefore aggregated years of
  runs nothing would read, and it was that volume rather than the feature that
  could not fit in the ClickHouse memory budget.

  The seam sits at the day this runs: the backfill ends there and the view
  carries everything after it. A reader that day asks for the 14 days before
  it, and every later day asks for a window the view has already covered more
  of, so the widest gap the backfill ever has to close is the read window
  itself. The extra days on top of it are slack, not coverage.

  The window cannot go to zero. `list_test_cases/3` renders a test case below
  the sample floor as "N/A" and explains it as "has run 0 times in the last 14
  days", which of an unseeded row is untrue rather than merely incomplete, and
  the Tests overview drops those rows from "Slowest test cases" entirely. The
  projects that would sit that way longest are the ones that run their suites
  least often: sampled against the current data, the four largest projects
  recover 94-99% of their populated duration cells after a single day of
  filling forward, while several low-frequency projects recover none of theirs
  in seven.

  ## Surviving the memory budget

  Every query the application issues shares one `max_memory_usage_for_user`
  ceiling with the running server, so a backfill that expands to fill the pool
  is picked off by the overcommit tracker and takes production headroom with it
  on the way. The insert therefore carries a per-query ceiling well under that
  budget and spills to disk rather than growing into it.

  A ceiling alone is not enough, because the same range passes or fails
  depending on what else the replica is doing, and an identical retry clears a
  marginal overrun but never a large one. A range that exhausts its retries is
  therefore halved by date and each half attempted in turn, down to a single
  day. Halves are disjoint in `date`, which is a grouping key, so every run is
  written into exactly one group however the range was cut.

  A single day that still does not fit is logged and skipped rather than
  raised. Raising would block every server release on one project's worst day,
  and the listing shows durations only above a minimum-sample floor and renders
  an empty cell below it, so a skipped day costs samples rather than showing an
  invented number.
  """
  use Ecto.Migration

  alias Tuist.IngestRepo

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  @backfill_window_days 16
  @project_throttle_ms 250
  @range_attempts 2
  @max_memory_usage 1_073_741_824
  @max_bytes_before_external_group_by 268_435_456

  def up do
    drop_objects()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE TABLE test_case_duration_daily_stats_per_case (
      project_id Int64,
      date Date,
      test_case_id UUID,
      is_ci Bool,
      run_count AggregateFunction(uniqExact, UUID),
      avg_duration AggregateFunction(avg, Int32),
      p50_duration AggregateFunction(quantile(0.5), Int32),
      p90_duration AggregateFunction(quantile(0.9), Int32),
      p99_duration AggregateFunction(quantile(0.99), Int32)
    ) ENGINE = AggregatingMergeTree
    PARTITION BY toYYYYMM(date)
    ORDER BY (project_id, test_case_id, date, is_ci)
    """)

    # The bounds are read from ClickHouse, not from the Elixir node, so they are
    # on the same clock as the `inserted_at` values they are compared against.
    {boundary, window_start, window_end} = backfill_bounds()

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("""
    CREATE MATERIALIZED VIEW test_case_duration_daily_stats_per_case_mv
    TO test_case_duration_daily_stats_per_case
    AS SELECT
      project_id,
      toDate(ran_at) AS date,
      assumeNotNull(test_case_id) AS test_case_id,
      is_ci,
      uniqExactState(id) AS run_count,
      avgState(duration) AS avg_duration,
      quantileState(0.5)(duration) AS p50_duration,
      quantileState(0.9)(duration) AS p90_duration,
      quantileState(0.99)(duration) AS p99_duration
    FROM test_case_runs
    WHERE test_case_id IS NOT NULL
    GROUP BY project_id, date, test_case_id, is_ci
    """)

    backfill(boundary, window_start, window_end)
  end

  def down do
    drop_objects()
  end

  defp drop_objects do
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP VIEW IF EXISTS test_case_duration_daily_stats_per_case_mv")

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    IngestRepo.query!("DROP TABLE IF EXISTS test_case_duration_daily_stats_per_case")
  end

  # Every run inserted from here on is picked up by the materialized view, so
  # the backfill covers exactly what came before and the two never overlap.
  #
  # The view is created after this instant is read, so runs inserted in the
  # moment between the two are seen by neither. That is deliberate: the reverse
  # order would have them seen by both, and a run counted twice can push a test
  # case over the minimum-sample floor, while a run missed for a few
  # milliseconds cannot.
  defp backfill_bounds do
    {:ok, %{rows: [[boundary, window_start, window_end]]}} =
      IngestRepo.query(
        """
        SELECT
          now64(6) AS boundary,
          toDate(boundary) - {days:UInt16} AS window_start,
          toDate(boundary) AS window_end
        """,
        %{days: @backfill_window_days}
      )

    Logger.info(
      "Backfilling test_case_duration_daily_stats_per_case over " <>
        "#{window_start}..#{window_end}, up to #{boundary}"
    )

    {boundary, window_start, window_end}
  end

  # Newest partition first. The listing reads the most recent days hardest, so
  # the feature is at its most complete as early as possible; an older
  # partition that needs several subdivisions delays nothing user-visible.
  #
  # A run whose `ran_at` falls in the window cannot have been ingested before
  # it, so partitions older than the window's own month hold nothing the window
  # admits.
  defp backfill(boundary, window_start, window_end) do
    for partition <- partitions_since(window_start) do
      project_ids = project_ids_for_partition(partition, window_start)

      Logger.info(
        "Backfilling partition #{partition} into test_case_duration_daily_stats_per_case " <>
          "(#{length(project_ids)} projects)"
      )

      Enum.each(project_ids, fn project_id ->
        backfill_range(partition, project_id, window_start, window_end, boundary)
        Process.sleep(@project_throttle_ms)
      end)
    end
  end

  defp partitions_since(window_start) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT partition
        FROM system.parts
        WHERE database = currentDatabase() AND table = {table:String} AND active
          AND toUInt32(partition) >= {min_partition:UInt32}
        ORDER BY partition DESC
        """,
        %{table: "test_case_runs", min_partition: year_month(window_start)}
      )

    Enum.map(rows, fn [partition] -> String.to_integer(partition) end)
  end

  defp project_ids_for_partition(partition, window_start) do
    {:ok, %{rows: rows}} =
      IngestRepo.query(
        """
        SELECT DISTINCT project_id
        FROM test_case_runs
        WHERE toYYYYMM(inserted_at) = {partition:UInt32}
          AND toDate(ran_at) >= {window_start:Date}
          AND project_id IS NOT NULL
          AND test_case_id IS NOT NULL
        ORDER BY project_id
        """,
        %{partition: partition, window_start: window_start},
        timeout: 600_000
      )

    Enum.map(rows, fn [project_id] -> project_id end)
  end

  defp backfill_range(
         partition,
         project_id,
         from_date,
         to_date,
         boundary,
         attempts \\ @range_attempts
       ) do
    insert_range(partition, project_id, from_date, to_date, boundary)
  rescue
    e in Ch.Error ->
      cond do
        not overrun?(e) ->
          reraise e, __STACKTRACE__

        attempts > 1 ->
          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}; " <>
              "retrying in 5s (#{attempts - 1} attempts left)"
          )

          Process.sleep(:timer.seconds(5))
          backfill_range(partition, project_id, from_date, to_date, boundary, attempts - 1)

        Date.compare(from_date, to_date) == :lt ->
          midpoint = Date.add(from_date, div(Date.diff(to_date, from_date), 2))

          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}; " <>
              "splitting at #{midpoint}"
          )

          backfill_range(partition, project_id, from_date, midpoint, boundary)
          backfill_range(partition, project_id, Date.add(midpoint, 1), to_date, boundary)

        true ->
          Logger.warning(
            "ClickHouse could not fit #{describe(project_id, from_date, to_date)}, " <>
              "the smallest range there is; skipping it"
          )
      end
  end

  # `toYYYYMM(inserted_at)` selects the source partition while `date` groups on
  # `ran_at`. Runs whose execution and ingestion fall on opposite sides of a
  # month boundary are therefore written from the partition that holds them,
  # into the destination partition their `ran_at` belongs to, so no run is
  # visited twice and none is skipped.
  defp insert_range(partition, project_id, from_date, to_date, boundary) do
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
        uniqExactState(id) AS run_count,
        avgState(duration) AS avg_duration,
        quantileState(0.5)(duration) AS p50_duration,
        quantileState(0.9)(duration) AS p90_duration,
        quantileState(0.99)(duration) AS p99_duration
      FROM test_case_runs
      WHERE toYYYYMM(inserted_at) = {partition:UInt32}
        AND inserted_at < {boundary:DateTime64(6)}
        AND project_id = {project_id:Int64}
        AND toDate(ran_at) >= {from_date:Date}
        AND toDate(ran_at) <= {to_date:Date}
        AND test_case_id IS NOT NULL
      GROUP BY project_id, date, test_case_id, is_ci
      SETTINGS
        optimize_aggregation_in_order = 1,
        max_threads = 1,
        max_memory_usage = #{@max_memory_usage},
        max_bytes_before_external_group_by = #{@max_bytes_before_external_group_by}
      """,
      %{
        partition: partition,
        project_id: project_id,
        from_date: from_date,
        to_date: to_date,
        boundary: boundary
      },
      timeout: 1_200_000
    )
  end

  # `TABLE_IS_READ_ONLY` is the replica briefly refusing writes rather than a
  # range that is too large, so it is worth the same retry and is harmless to
  # subdivide when the retry does not clear it.
  defp overrun?(%Ch.Error{} = error) do
    message = to_string(error.message)

    String.contains?(message, "MEMORY_LIMIT_EXCEEDED") or
      String.contains?(message, "TABLE_IS_READ_ONLY")
  end

  defp describe(project_id, from_date, to_date) do
    "project #{project_id} over #{from_date}..#{to_date}"
  end

  defp year_month(%Date{year: year, month: month}), do: year * 100 + month
end
