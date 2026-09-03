defmodule Tuist.Automations.Monitors.FlakyTestsMonitor do
  @moduledoc """
  Evaluates flaky-test alerts.

  Each alert is parameterised by:

    * `monitor_type` — what's being measured (`flakiness_rate`,
      `flaky_run_count`, or `reliability_rate`)
    * `trigger_config.comparison` — how to compare the measurement to the
      threshold (`gte`, `gt`, `lt`, `lte`; defaults to `gte` for
      flakiness/count monitors and `lt` for reliability)
    * `trigger_config.window_type` — `"last_days"` evaluates over a calendar
      window (configured via `window: "30d"`); `"rolling"` evaluates the
      latest N runs per test case (configured via `rolling_window_size`).
      Defaults to `"last_days"` for alerts created before the rolling option
      existed.

  The candidate set is always "test cases with at least one run in the
  window." Tests with no runs are excluded because they have nothing to
  measure. Whether a test case enters or leaves the matching set drives
  the worker's transition logic — this module just reports the current
  match; the worker silences the initial baseline so users don't get
  flooded for the established state.

  All four comparison directions for `last_days` read the
  `test_case_run_daily_stats_per_case` AggregatingMergeTree, ordered by
  `(project_id, date, test_case_id)`. A 30-day evaluation reads ~30 rows
  per test case for the project — bounded prefix scan rather than a
  full-table walk on `test_case_runs` (which is keyed on
  `(test_run_id, …)` and would have to filter `project_id` after reading
  every granule in the relevant monthly partitions).

  The `rolling` mode reads `test_case_runs_recent_window_per_case`, whose single
  `groupArraySorted(2000)` state packs each run into one `Int64`
  (`-ran_at_micros * 4 + is_flaky * 2 + is_success`). One column therefore serves
  flakiness, flaky-run-count, and reliability, since each monitor just reads a
  different bit.

  The encoding is what makes a large window affordable. Holding the same runs as
  `(-ran_at_micros, flag)` tuples puts `groupArraySorted` on ClickHouse's generic
  comparator and needs a second parallel column for the other flag: merging a
  1000-entry tuple state across a 2000-test-case range costs 650 MiB against this
  module's 1 GiB ceiling, where the packed state serves a 1000-run window in
  61 MiB. The bucket holds twice the window cap so the correction rows that flaky
  detection re-inserts cannot push a distinct run out of the window.

  A window is evaluated only once the aggregate holds that many distinct runs.
  A rolling window measures the last N runs, so it means nothing until N runs
  exist to measure; reporting a rate off whatever has accrued answers a question
  the user did not ask, and at small run counts it is noise that auto-quarantine
  would act on.

  When several alerts use the same rolling window and aggregate column, the
  ingestion-driven worker calls `evaluate_rolling_alerts/2`. That query returns
  the numerator and run count once per affected test case, then applies each
  alert's threshold in Elixir. This avoids repeating the same aggregate-state
  merge for alerts that only differ by threshold or by rate-versus-count.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCaseRunDailyStatsPerCase

  @comparisons ~w(gte gt lt lte)

  # Legacy persisted values are still parsed up to the old product ceiling so
  # execution can reject them explicitly instead of silently truncating them.
  @max_rolling_window_size 1000
  @default_rolling_window_size 100

  # Sized at twice the window cap so a window is exact even when every run in it
  # was corrected, given the at-most-two physical rows per logical run that
  # `Tests.report_test_case_run_multiplicity/3` enforces.
  #
  # De-duplicating inside the aggregate instead, so the bucket could equal the
  # cap, is not available. `-Distinct` is a generic combinator: it filters the
  # argument stream before the inner aggregate sees it, so it holds a hash set of
  # every distinct argument and cannot prune that set to the inner bound. It
  # knows nothing about the aggregate it wraps, and forgetting a value would
  # break `countDistinct`, which has no bound to prune to.
  #
  # The bound therefore never touches the set. Over 200,000 distinct values,
  # `groupArraySortedDistinctState` measures 1.53 MiB at a bound of 10 and the
  # same 1.53 MiB at 1000, where `groupArraySorted` holds 89 bytes at any input
  # size; `sumDistinct` measures 1.53 MiB over that input against 16 bytes for
  # `sum`, which is where the growth actually lives. Storage, merges, and reads
  # would all then scale with a test case's entire run history rather than with
  # the window — the shape that retired the earlier aggregates, with no bound
  # this time. The headroom is the cheaper trade.
  @recent_runs_bucket_size 2000
  @max_active_rolling_window_size 1000

  # Merging the rolling aggregate states is memory-heavy and memory grows with
  # parallelism. Keep this limit local to these queries so concurrent alert
  # evaluations leave headroom for runner lifecycle writes and other reads.
  @rolling_query_settings [
    max_threads: 2,
    max_memory_usage: 1024 * 1024 * 1024
  ]

  # Parallel aggregates carrying only runs on the project's default branch. They
  # are separate tables rather than a dimension on the shared ones because a
  # branch dimension multiplies those tables 14-86x on production projects, and a
  # boolean cannot be added to an existing sort key without every row already
  # written claiming the wrong value. See the two migrations for the numbers.
  @default_branch_daily_table "test_case_run_daily_stats_per_case_default_branch"
  @default_branch_recent_window_table "test_case_runs_default_branch_recent_window_per_case"
  @all_branches_daily_table "test_case_run_daily_stats_per_case"
  @all_branches_recent_window_table "test_case_runs_recent_window_per_case"

  # A calendar window has no natural minimum the way a rolling window does: it
  # will happily compute a rate off whatever landed in it. That was tolerable
  # while reliability read every branch, where a 30-day window holds a test
  # case's whole run history. Scoping to the trunk cuts each sample to a
  # fraction of that — the default branch is 13.3% of runs on the production
  # project this was measured against — and the aggregate also starts empty,
  # since nothing backfills it.
  #
  # Ten is where one failure sits exactly on the common 90% threshold rather
  # than under it, so a single bad run cannot by itself quarantine a test. Below
  # the floor a test case is not measured at all, which is the same answer the
  # rolling path gives an unfilled window, and `measurable_test_case_ids/2`
  # keeps recovery from reading that silence as the condition clearing.
  @min_scoped_samples 10

  @doc """
  Which runs an alert measures.

  Reliability answers "is this test trustworthy", which is a question about the
  trunk, so it measures the default branch. Flakiness answers "does this test
  waste developers' time", which is true wherever it happens, so it stays on
  every branch.

  A project with no default branch configured has no trunk to scope to, so its
  scoped aggregate holds nothing and a reliability alert has nothing to measure
  until one is set.
  """
  def branch_scope(%{monitor_type: "reliability_rate"}), do: :default_branch
  def branch_scope(_alert), do: :all_branches

  @doc """
  The subset of `test_case_ids` this alert can currently measure.

  Recovery treats "not in the triggered set" as "the condition cleared", which
  is only true of a test case that was actually measured. Under default-branch
  scoping that stops being a safe assumption: a quarantined test whose runs move
  entirely onto pull-request branches disappears from the triggered set because
  there is nothing left to measure, and recovery would read that as proof it got
  better and un-quarantine it.

  Flakiness alerts are deliberately not filtered. Their existing behaviour, that a
  test case with fewer runs than its window stops being measured and lets
  recovery re-arm, is documented at `window_filled_expr/1` and is not this
  change's to alter.
  """
  def measurable_test_case_ids(_alert, []), do: []

  def measurable_test_case_ids(alert, test_case_ids) do
    case branch_scope(alert) do
      :all_branches ->
        test_case_ids

      :default_branch ->
        case window_mode(alert.trigger_config) do
          {:last_days, seconds} -> measured_in_calendar_window(alert, seconds, test_case_ids)
          {:rolling, size} -> measured_in_rolling_window(alert, size, test_case_ids)
        end
    end
  end

  # Applies the same floor the trigger query does, so "measurable" means one
  # thing on both paths. A test case with runs but not enough of them is no more
  # recoverable than one with none.
  defp measured_in_calendar_window(alert, seconds, test_case_ids) do
    cutoff = window_cutoff_date(seconds)

    ClickHouseRepo.all(
      from(daily in {@default_branch_daily_table, TestCaseRunDailyStatsPerCase},
        where: daily.project_id == ^alert.project_id,
        where: daily.date >= ^cutoff,
        where: daily.test_case_id in ^test_case_ids,
        group_by: daily.test_case_id,
        having: fragment("countMerge(run_count) >= ?", ^@min_scoped_samples),
        select: daily.test_case_id
      )
    )
  end

  # A rolling window is measurable exactly when it is filled, which is the same
  # predicate the trigger query applies, so this reuses the measurement path and
  # keeps the two from drifting apart.
  defp measured_in_rolling_window(alert, size, test_case_ids) do
    alert.project_id
    |> rolling_measurements(:default_branch, matching_flag(alert.monitor_type), size, test_case_ids)
    |> Enum.map(&elem(&1, 0))
  end

  defp apply_sample_floor(query, :all_branches), do: query

  defp apply_sample_floor(query, :default_branch),
    do: having(query, fragment("countMerge(run_count) >= ?", ^@min_scoped_samples))

  defp daily_stats_source(:default_branch), do: @default_branch_daily_table
  defp daily_stats_source(:all_branches), do: @all_branches_daily_table

  defp recent_window_table(:default_branch), do: @default_branch_recent_window_table
  defp recent_window_table(:all_branches), do: @all_branches_recent_window_table

  def evaluate(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id
    scope = branch_scope(alert)
    source = daily_stats_source(scope)

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          source
          |> flakiness_rate_last_days_query(
            project_id,
            window_cutoff_date(seconds),
            threshold,
            comparison
          )
          |> apply_sample_floor(scope)
          |> filter_test_case_ids(test_case_ids)
          |> ClickHouseRepo.all()

        {:rolling, size} ->
          rolling_triggered_test_case_ids(project_id, scope, "flakiness_rate", size, threshold, comparison, test_case_ids)
      end

    %{triggered: triggered_test_case_ids}
  end

  def evaluate_by_run_count(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 1
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id
    scope = branch_scope(alert)
    source = daily_stats_source(scope)

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          source
          |> flaky_run_count_last_days_query(
            project_id,
            window_cutoff_date(seconds),
            threshold,
            comparison
          )
          |> apply_sample_floor(scope)
          |> filter_test_case_ids(test_case_ids)
          |> ClickHouseRepo.all()

        {:rolling, size} ->
          rolling_triggered_test_case_ids(
            project_id,
            scope,
            "flaky_run_count",
            size,
            threshold,
            comparison,
            test_case_ids
          )
      end

    %{triggered: triggered_test_case_ids}
  end

  def evaluate_by_reliability_rate(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 90
    comparison = parse_comparison(trigger_config["comparison"], "lt")
    project_id = alert.project_id
    scope = branch_scope(alert)
    source = daily_stats_source(scope)

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          source
          |> reliability_rate_last_days_query(
            project_id,
            window_cutoff_date(seconds),
            threshold,
            comparison
          )
          |> apply_sample_floor(scope)
          |> filter_test_case_ids(test_case_ids)
          |> ClickHouseRepo.all()

        {:rolling, size} ->
          rolling_triggered_test_case_ids(
            project_id,
            scope,
            "reliability_rate",
            size,
            threshold,
            comparison,
            test_case_ids
          )
      end

    %{triggered: triggered_test_case_ids}
  end

  def rolling_group_key(%{monitor_type: monitor_type, trigger_config: trigger_config} = alert)
      when monitor_type in ["flakiness_rate", "flaky_run_count", "reliability_rate"] do
    case window_mode(trigger_config) do
      {:rolling, size} -> {:rolling, branch_scope(alert), matching_flag(monitor_type), size}
      {:last_days, _seconds} -> nil
    end
  end

  def rolling_group_key(_alert), do: nil

  def evaluate_rolling_alerts([], _test_case_ids), do: %{}

  def evaluate_rolling_alerts([alert | _alerts] = alerts, test_case_ids) do
    {:rolling, scope, column, size} = rolling_group_key(alert)
    measurements = rolling_measurements(alert.project_id, scope, column, size, test_case_ids)

    Map.new(alerts, fn alert ->
      triggered_test_case_ids =
        measurements
        |> Enum.filter(&measurement_triggers_alert?(&1, alert))
        |> Enum.map(&elem(&1, 0))

      {alert.id, triggered_test_case_ids}
    end)
  end

  # The MV is keyed on `(project_id, date, test_case_id)`, so we round the
  # cutoff to the start of the day. A 30-day window evaluated mid-day picks
  # up a few hours of additional data on day -30 — acceptable for
  # threshold-based alerts and well within the noise of test-run timing.
  defp window_cutoff_date(window_seconds) do
    DateTime.utc_now()
    |> DateTime.add(-window_seconds, :second)
    |> DateTime.to_date()
  end

  # Ecto's `fragment(...)` macro requires a literal first argument to prevent
  # SQL-injection routes, so each comparison gets its own clause instead of
  # an interpolated operator.
  defp flakiness_rate_last_days_query(source, project_id, cutoff_date, threshold, "gte") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(flaky_run_count) * 100.0 / countMerge(run_count) >= ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp flakiness_rate_last_days_query(source, project_id, cutoff_date, threshold, "gt") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(flaky_run_count) * 100.0 / countMerge(run_count) > ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp flakiness_rate_last_days_query(source, project_id, cutoff_date, threshold, "lt") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(flaky_run_count) * 100.0 / countMerge(run_count) < ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp flakiness_rate_last_days_query(source, project_id, cutoff_date, threshold, "lte") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(flaky_run_count) * 100.0 / countMerge(run_count) <= ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(source, project_id, cutoff_date, threshold, "gte") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) >= ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(source, project_id, cutoff_date, threshold, "gt") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) > ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(source, project_id, cutoff_date, threshold, "lt") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) < ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(source, project_id, cutoff_date, threshold, "lte") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) <= ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp reliability_rate_last_days_query(source, project_id, cutoff_date, threshold, "gte") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(successful_run_count) * 100.0 / countMerge(run_count) >= ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp reliability_rate_last_days_query(source, project_id, cutoff_date, threshold, "gt") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(successful_run_count) * 100.0 / countMerge(run_count) > ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp reliability_rate_last_days_query(source, project_id, cutoff_date, threshold, "lt") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(successful_run_count) * 100.0 / countMerge(run_count) < ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  defp reliability_rate_last_days_query(source, project_id, cutoff_date, threshold, "lte") do
    from(daily in {source, TestCaseRunDailyStatsPerCase},
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having:
        fragment(
          "sumMerge(successful_run_count) * 100.0 / countMerge(run_count) <= ?",
          ^threshold
        ),
      select: daily.test_case_id
    )
  end

  # The rolling fast path reads whichever per-test-case aggregate
  # `recent_runs_source/2` selects for the window. Either way the scan is
  # bounded by `active_test_cases_in_project` rather than total run volume —
  # usually a few thousand rows — and the merged array is already latest-first
  # before the final user-configured slice, because both buckets sort on a
  # negated run timestamp.
  #
  # `test_case_runs` is a ReplacingMergeTree and flaky detection re-inserts a
  # run to set `is_flaky` after ingestion, so the materialized view can absorb
  # the same logical run several times. Those duplicates concentrate on
  # flaky/failed runs — a passing run is never re-marked — so counting raw
  # array entries inflates flakiness and deflates reliability for exactly the
  # runs a threshold reacts to.
  # `rolling_triggered_test_case_ids_from_recent_runs` collapses the array to
  # one entry per run (keyed on `ran_at`) before computing a rate.
  #
  # `monitor_type`, `comparison`, `table`, `ordered_runs_expr`,
  # `matching_flag_expr`, `window_filled_expr`, and `deduplicated_runs_expr` are
  # interpolated because they are chosen from fixed in-module allowlists (or are
  # validated integers via `size`), so there is no query-injection vector.
  # `project_id` and `threshold` flow through bound parameters.
  defp rolling_triggered_test_case_ids(project_id, scope, monitor_type, size, threshold, comparison, test_case_ids) do
    source = recent_runs_source(scope, matching_flag(monitor_type), size)

    rolling_triggered_test_case_ids_from_recent_runs(
      source,
      project_id,
      monitor_type,
      size,
      threshold,
      comparison,
      test_case_ids
    )
  end

  defp rolling_measurements(_project_id, _scope, _column, _size, []), do: []

  defp rolling_measurements(project_id, scope, column, size, test_case_ids) do
    source = recent_runs_source(scope, column, size)
    rolling_measurements_from_recent_runs(source, project_id, size, test_case_ids)
  end

  defp rolling_measurements_from_recent_runs({table, ordered_runs_expr, flag}, project_id, size, test_case_ids) do
    deduplicated_runs_expr = deduplicated_runs_expr()

    sql = """
    SELECT
      test_case_id,
      arraySum(#{matching_flag_expr(flag)}, recent_runs) AS matching_run_count,
      length(recent_runs) AS run_count
    FROM (
      SELECT
        test_case_id,
        arraySlice(
          #{deduplicated_runs_expr},
          1,
          #{size}
        ) AS recent_runs
      FROM (
        SELECT
          test_case_id,
          #{ordered_runs_expr} AS ordered_runs
        FROM #{table}
        WHERE project_id = {project_id:Int64}
          AND test_case_id IN {test_case_ids:Array(UUID)}
        GROUP BY test_case_id
      )
    )
    WHERE #{window_filled_expr(size)}
    """

    %{rows: rows} =
      ClickHouseRepo.query!(
        sql,
        %{
          project_id: project_id,
          test_case_ids: test_case_ids
        },
        settings: @rolling_query_settings
      )

    Enum.map(rows, fn [binary, matching_run_count, run_count] ->
      {Ecto.UUID.load!(binary), matching_run_count, run_count}
    end)
  end

  defp measurement_triggers_alert?({_test_case_id, matching_run_count, run_count}, alert) do
    threshold = alert_threshold(alert)

    value =
      case alert.monitor_type do
        "flaky_run_count" -> matching_run_count
        _rate -> matching_run_count * 100.0 / run_count
      end

    comparison_matches?(value, threshold, alert_comparison(alert))
  end

  defp alert_threshold(%{monitor_type: "flaky_run_count", trigger_config: trigger_config}),
    do: trigger_config["threshold"] || 1

  defp alert_threshold(%{monitor_type: "reliability_rate", trigger_config: trigger_config}),
    do: trigger_config["threshold"] || 90

  defp alert_threshold(%{trigger_config: trigger_config}), do: trigger_config["threshold"] || 10

  defp alert_comparison(%{monitor_type: "reliability_rate", trigger_config: trigger_config}),
    do: parse_comparison(trigger_config["comparison"], "lt")

  defp alert_comparison(%{trigger_config: trigger_config}), do: parse_comparison(trigger_config["comparison"])

  defp comparison_matches?(value, threshold, "gte"), do: value >= threshold
  defp comparison_matches?(value, threshold, "gt"), do: value > threshold
  defp comparison_matches?(value, threshold, "lt"), do: value < threshold
  defp comparison_matches?(value, threshold, "lte"), do: value <= threshold

  # Reliability measures successful runs; flakiness and count measure flaky
  # runs. Both live as parallel `(sort_key, flag)` aggregates on the same
  # rolling-window tables, so the routing below is identical and only the
  # aggregate column differs.
  defp matching_flag("reliability_rate"), do: :success
  defp matching_flag(_monitor_type), do: :flaky

  # Returns `{table, ordered_runs_expr, flag}`. `ordered_runs_expr` merges the
  # full per-test-case aggregate in latest-first order. The bucket negates the
  # run timestamp in its sorted state, so the reader only needs a linear pass to
  # collapse duplicates. `flag` selects which of the two bits packed into each
  # entry the monitor measures.
  defp recent_runs_source(_scope, _flag, size) when size > @max_active_rolling_window_size do
    raise ArgumentError, "rolling trigger windows must be at most #{@max_active_rolling_window_size}"
  end

  defp recent_runs_source(scope, flag, _size) do
    {
      recent_window_table(scope),
      "groupArraySortedMerge(#{@recent_runs_bucket_size})(recent_runs)",
      flag
    }
  end

  # Each entry keeps `is_flaky` in bit 1 and `is_success` in bit 0, below the
  # scaled timestamp. `reinterpretAsUInt64` is what makes the bit reads
  # well-defined: entries are negative, and neither `intDiv` nor a signed shift
  # is consistent across the sign boundary.
  defp matching_flag_expr(:success), do: "entry -> bitAnd(reinterpretAsUInt64(entry), 1)"

  defp matching_flag_expr(:flaky), do: "entry -> bitAnd(bitShiftRight(reinterpretAsUInt64(entry), 1), 1)"

  # A rolling window measures the last N runs, so it is only meaningful once N
  # distinct runs exist to measure. Reporting a rate off whatever has accrued so
  # far answers a question the user did not ask, and at small run counts it is
  # noise that auto-quarantine would act on.
  #
  # This governs every window size, not only the large ones the packed aggregate
  # was introduced for. Before one aggregate served every window, sizes at or
  # below the tuple bucket's ceiling evaluated whatever had accrued; they now
  # wait like any other. A test case with fewer runs than its window asks about
  # therefore stops being measured, which lets recovery re-arm it.
  defp window_filled_expr(size), do: "length(recent_runs) >= #{size}"

  defp rolling_triggered_test_case_ids_from_recent_runs(
         {table, ordered_runs_expr, flag},
         project_id,
         monitor_type,
         size,
         threshold,
         comparison,
         test_case_ids
       ) do
    test_case_filter =
      case test_case_ids do
        nil -> ""
        _test_case_ids -> "AND test_case_id IN {test_case_ids:Array(UUID)}"
      end

    deduplicated_runs_expr = deduplicated_runs_expr()

    # Collapse the bounded per-test-case array to one entry per run, keyed on
    # the run's `ran_at` in microseconds and keeping the largest flag so a run
    # that was ever re-marked flaky / ever succeeded is represented once with
    # the right flag. Then keep the latest `size` distinct runs and compute the
    # rate over those, so a re-inserted run can no longer be counted more than
    # once. Keeping the work inside arrays avoids the expensive
    # ARRAY JOIN + GROUP BY + LIMIT BY shape that multiplied each active test
    # case into hundreds of rows.
    sql = """
    SELECT test_case_id
    FROM (
      SELECT
        test_case_id,
        arraySlice(
          #{deduplicated_runs_expr},
          1,
          #{size}
        ) AS recent_runs
      FROM (
        SELECT
          test_case_id,
          #{ordered_runs_expr} AS ordered_runs
        FROM #{table}
        WHERE project_id = {project_id:Int64}
          #{test_case_filter}
        GROUP BY test_case_id
      )
    )
    WHERE #{window_filled_expr(size)}
      AND #{rolling_having_expr(monitor_type, matching_flag_expr(flag))} #{rolling_comparison_op(comparison)} {threshold:Float64}
    """

    params = maybe_put_test_case_ids(%{project_id: project_id, threshold: threshold * 1.0}, test_case_ids)

    # Raise on ClickHouse errors instead of swallowing them. If the materialized
    # view is missing or the query fails transiently, returning `[]` would tell
    # the worker "no test cases match" and trip recovery actions on every
    # active event. Letting the error propagate matches the
    # `ClickHouseRepo.all` path in the `last_days` branch and gives Oban a
    # chance to retry.
    %{rows: rows} = ClickHouseRepo.query!(sql, params, settings: @rolling_query_settings)

    # ClickHouse returns identifier columns as 16-byte binaries here; the rest
    # of the worker compares against string-encoded identifiers from the Ecto
    # path, so normalise.
    Enum.map(rows, fn [binary] -> Ecto.UUID.load!(binary) end)
  end

  # Bucket states are sorted ascending on a negated run timestamp, so runs are
  # newest-first and the entries of one logical run are adjacent, with the
  # largest flag last. Comparing every entry's run key with the next entry's
  # keeps that last entry in a linear pass. The positive sentinel cannot collide
  # with the negative timestamp keys stored in either bucket.
  # Entries are sorted ascending on a negated run timestamp, so runs are
  # newest-first and the entries of one logical run are adjacent, with the
  # largest flag last. An entry's run key is everything above the two flag bits,
  # so a correction row and the run it corrects differ only below the shift.
  # Comparing every entry's run key with the next entry's keeps that last entry
  # in a linear pass. The positive sentinel cannot collide with the negative
  # timestamp keys stored in the bucket.
  defp deduplicated_runs_expr do
    """
    arrayFilter(
      (entry, next_entry) ->
        bitShiftRight(reinterpretAsUInt64(entry), 2) != bitShiftRight(reinterpretAsUInt64(next_entry), 2),
      ordered_runs,
      arrayShiftLeft(
        ordered_runs,
        1,
        toInt64(9223372036854775807)
      )
    )
    """
  end

  defp rolling_having_expr("flakiness_rate", flag_expr),
    do: "arraySum(#{flag_expr}, recent_runs) * 100.0 / length(recent_runs)"

  defp rolling_having_expr("flaky_run_count", flag_expr), do: "arraySum(#{flag_expr}, recent_runs)"

  defp rolling_having_expr("reliability_rate", flag_expr),
    do: "arraySum(#{flag_expr}, recent_runs) * 100.0 / length(recent_runs)"

  defp rolling_comparison_op("gte"), do: ">="
  defp rolling_comparison_op("gt"), do: ">"
  defp rolling_comparison_op("lt"), do: "<"
  defp rolling_comparison_op("lte"), do: "<="

  defp maybe_put_test_case_ids(params, nil), do: params
  defp maybe_put_test_case_ids(params, test_case_ids), do: Map.put(params, :test_case_ids, test_case_ids)

  defp filter_test_case_ids(query, nil), do: query
  defp filter_test_case_ids(query, []), do: where(query, false)

  defp filter_test_case_ids(query, test_case_ids) do
    where(query, [row], row.test_case_id in ^test_case_ids)
  end

  # Persisted alerts always carry an explicit `window_type` after the backfill
  # migration, so we only handle the two known modes. The catch-all clause
  # protects against malformed in-memory data slipping through.
  defp window_mode(%{"window_type" => "rolling"} = config),
    do: {:rolling, parse_rolling_size(config["rolling_window_size"])}

  defp window_mode(%{"window_type" => "last_days"} = config), do: {:last_days, parse_window(config["window"] || "30d")}

  defp window_mode(config), do: {:last_days, parse_window(config["window"] || "30d")}

  # `Alert.changeset/2` constrains `trigger_config.window` to `Nd`, so we
  # only need to handle day-suffixed strings here. Non-matching values fall
  # back to the default 30 days for legacy/garbage data.
  defp parse_window(window) when is_binary(window) do
    case Integer.parse(window) do
      {value, "d"} when value > 0 -> value * 86_400
      _ -> 30 * 86_400
    end
  end

  defp parse_window(_), do: 30 * 86_400

  defp parse_rolling_size(size) when is_integer(size) and size > 0, do: min(size, @max_rolling_window_size)
  defp parse_rolling_size(_), do: @default_rolling_window_size

  # `gte` is the historical default before alerts had a comparison field; keep
  # it as the fallback for existing flakiness/count alerts so their behaviour
  # does not change. Reliability is new and defaults to the unhealthy
  # direction (`lt`).
  defp parse_comparison(comparison, _default \\ "gte")
  defp parse_comparison(comparison, _default) when comparison in @comparisons, do: comparison
  defp parse_comparison(_, default), do: default
end
