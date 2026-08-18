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

  The `rolling` mode reads `test_case_runs_recent_window_per_case`, which keeps
  three `groupArraySortedDistinct(1000)` states of `-ran_at_micros` run keys per
  test case: every run, the flaky ones, and the successful ones. A monitor
  intersects the window with whichever flag column it measures.

  The encoding is what makes a large window affordable. Holding the same runs as
  `(-ran_at_micros, flag)` tuples puts `groupArraySorted` on ClickHouse's generic
  comparator: merging a 1000-entry tuple state across a 2000-test-case range
  costs 650 MiB against this module's 1 GiB ceiling, where plain run keys serve a
  1000-run window in 186 MiB.

  `Distinct` is what makes the window exact. `test_case_runs` is a
  ReplacingMergeTree and flaky detection re-inserts a run to set `is_flaky`, so
  one logical run reaches the view as several physical rows. The combinator
  collapses them on the run key, and the collapse survives state merges, so a run
  occupies one slot however often it was re-inserted. The bucket is therefore the
  window cap rather than a multiple of it, and nothing has to be de-duplicated at
  read time.

  Flag membership replaces flag reconciliation. Because `flaky_runs` and
  `successful_runs` hold the most recent keys of their kind, and a run inside the
  window is among the most recent runs overall, a flagged run in the window is
  always present in its flag column. Counting the flag is therefore counting the
  flag keys that fall inside the window's range.

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

  # The aggregate de-duplicates on the run key, so the bucket is the window cap
  # rather than a multiple of it.
  @recent_runs_bucket_size 1000
  @max_active_rolling_window_size 1000

  # Merging the rolling aggregate states is memory-heavy and memory grows with
  # parallelism. Keep this limit local to these queries so concurrent alert
  # evaluations leave headroom for runner lifecycle writes and other reads.
  @rolling_query_settings [
    max_threads: 2,
    max_memory_usage: 1024 * 1024 * 1024
  ]

  def evaluate(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          project_id
          |> flakiness_rate_last_days_query(window_cutoff_date(seconds), threshold, comparison)
          |> filter_test_case_ids(test_case_ids)
          |> ClickHouseRepo.all()

        {:rolling, size} ->
          rolling_triggered_test_case_ids(project_id, "flakiness_rate", size, threshold, comparison, test_case_ids)
      end

    %{triggered: triggered_test_case_ids}
  end

  def evaluate_by_run_count(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 1
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          project_id
          |> flaky_run_count_last_days_query(window_cutoff_date(seconds), threshold, comparison)
          |> filter_test_case_ids(test_case_ids)
          |> ClickHouseRepo.all()

        {:rolling, size} ->
          rolling_triggered_test_case_ids(project_id, "flaky_run_count", size, threshold, comparison, test_case_ids)
      end

    %{triggered: triggered_test_case_ids}
  end

  def evaluate_by_reliability_rate(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 90
    comparison = parse_comparison(trigger_config["comparison"], "lt")
    project_id = alert.project_id

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          project_id
          |> reliability_rate_last_days_query(window_cutoff_date(seconds), threshold, comparison)
          |> filter_test_case_ids(test_case_ids)
          |> ClickHouseRepo.all()

        {:rolling, size} ->
          rolling_triggered_test_case_ids(project_id, "reliability_rate", size, threshold, comparison, test_case_ids)
      end

    %{triggered: triggered_test_case_ids}
  end

  def rolling_group_key(%{monitor_type: monitor_type, trigger_config: trigger_config})
      when monitor_type in ["flakiness_rate", "flaky_run_count", "reliability_rate"] do
    case window_mode(trigger_config) do
      {:rolling, size} -> {:rolling, matching_flag(monitor_type), size}
      {:last_days, _seconds} -> nil
    end
  end

  def rolling_group_key(_alert), do: nil

  def evaluate_rolling_alerts([], _test_case_ids), do: %{}

  def evaluate_rolling_alerts([alert | _alerts] = alerts, test_case_ids) do
    {:rolling, column, size} = rolling_group_key(alert)
    measurements = rolling_measurements(alert.project_id, column, size, test_case_ids)

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
  defp flakiness_rate_last_days_query(project_id, cutoff_date, threshold, "gte") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp flakiness_rate_last_days_query(project_id, cutoff_date, threshold, "gt") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp flakiness_rate_last_days_query(project_id, cutoff_date, threshold, "lt") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp flakiness_rate_last_days_query(project_id, cutoff_date, threshold, "lte") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp flaky_run_count_last_days_query(project_id, cutoff_date, threshold, "gte") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) >= ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(project_id, cutoff_date, threshold, "gt") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) > ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(project_id, cutoff_date, threshold, "lt") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) < ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_last_days_query(project_id, cutoff_date, threshold, "lte") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) <= ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp reliability_rate_last_days_query(project_id, cutoff_date, threshold, "gte") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp reliability_rate_last_days_query(project_id, cutoff_date, threshold, "gt") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp reliability_rate_last_days_query(project_id, cutoff_date, threshold, "lt") do
    from(daily in TestCaseRunDailyStatsPerCase,
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

  defp reliability_rate_last_days_query(project_id, cutoff_date, threshold, "lte") do
    from(daily in TestCaseRunDailyStatsPerCase,
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
  # `monitor_type`, `comparison`, `table`, `window_expr`, `flag_expr`, and
  # `window_filled_expr` are interpolated because they are chosen from fixed
  # in-module allowlists (or are validated integers via `size`), so there is no
  # query-injection vector. `project_id` and `threshold` flow through bound
  # parameters.
  defp rolling_triggered_test_case_ids(project_id, monitor_type, size, threshold, comparison, test_case_ids) do
    source = recent_runs_source(matching_flag(monitor_type), size)

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

  defp rolling_measurements(_project_id, _column, _size, []), do: []

  defp rolling_measurements(project_id, column, size, test_case_ids) do
    source = recent_runs_source(column, size)
    rolling_measurements_from_recent_runs(source, project_id, size, test_case_ids)
  end

  defp rolling_measurements_from_recent_runs({table, window_expr, flag_expr}, project_id, size, test_case_ids) do
    sql = """
    SELECT
      test_case_id,
      #{matching_run_count_expr()} AS matching_run_count,
      length(recent_runs) AS run_count
    FROM (
      SELECT
        test_case_id,
        arraySlice(#{window_expr}, 1, #{size}) AS recent_runs,
        #{flag_expr} AS flag_runs
      FROM #{table}
      WHERE project_id = {project_id:Int64}
        AND test_case_id IN {test_case_ids:Array(UUID)}
      GROUP BY test_case_id
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

  # Returns `{table, window_expr, flag_expr}`. Both merge the per-test-case
  # states; the run keys are negated timestamps, so ascending order is
  # latest-first and the window is a plain prefix.
  defp recent_runs_source(_flag, size) when size > @max_active_rolling_window_size do
    raise ArgumentError, "rolling trigger windows must be at most #{@max_active_rolling_window_size}"
  end

  defp recent_runs_source(flag, _size) do
    {
      "test_case_runs_recent_window_per_case",
      "groupArraySortedDistinctMerge(#{@recent_runs_bucket_size})(recent_runs)",
      "groupArraySortedDistinctMerge(#{@recent_runs_bucket_size})(#{flag_column(flag)})"
    }
  end

  defp flag_column(:success), do: "successful_runs"
  defp flag_column(:flaky), do: "flaky_runs"

  # The window holds every run key at or below its oldest entry, and a flagged
  # run in the window is always present in its flag column, so counting the flag
  # keys that reach back no further than the window's oldest run counts exactly
  # the flagged runs inside it. That is a linear pass over an already sorted
  # array rather than a set intersection.
  defp matching_run_count_expr, do: "arrayCount(entry -> entry <= recent_runs[-1], flag_runs)"

  # A rolling window measures the last N runs, so it is only meaningful once N
  # distinct runs exist to measure. Reporting a rate off whatever has accrued so
  # far answers a question the user did not ask, and at small run counts it is
  # noise that auto-quarantine would act on.
  defp window_filled_expr(size), do: "length(recent_runs) >= #{size}"

  defp rolling_triggered_test_case_ids_from_recent_runs(
         {table, window_expr, flag_expr},
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

    sql = """
    SELECT test_case_id
    FROM (
      SELECT
        test_case_id,
        arraySlice(#{window_expr}, 1, #{size}) AS recent_runs,
        #{flag_expr} AS flag_runs
      FROM #{table}
      WHERE project_id = {project_id:Int64}
        #{test_case_filter}
      GROUP BY test_case_id
    )
    WHERE #{window_filled_expr(size)}
      AND #{rolling_having_expr(monitor_type)} #{rolling_comparison_op(comparison)} {threshold:Float64}
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

  defp rolling_having_expr("flakiness_rate"), do: "#{matching_run_count_expr()} * 100.0 / length(recent_runs)"

  defp rolling_having_expr("flaky_run_count"), do: matching_run_count_expr()

  defp rolling_having_expr("reliability_rate"), do: "#{matching_run_count_expr()} * 100.0 / length(recent_runs)"

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
