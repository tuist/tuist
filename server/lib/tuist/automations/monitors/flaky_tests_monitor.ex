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

  The `rolling` mode reads `test_case_runs_recent_100_per_case`, the only
  aggregate kept active during the rolling-storage replacement. Trigger
  windows are temporarily capped below 100 runs, while recovery continues to
  read raw runs. The table carries both a flaky aggregate (`recent_runs`) and a
  success aggregate (`recent_successful_runs`), so flakiness, flaky-run-count,
  and reliability monitors take the same path.

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
  @default_rolling_window_size 75
  @active_recent_runs_bucket_size 100
  @max_active_rolling_window_size 99

  # Merging the rolling aggregate states is memory-heavy and memory grows with
  # parallelism. Keep this limit local to these queries so concurrent alert
  # evaluations leave headroom for runner lifecycle writes and other reads.
  @rolling_query_max_threads 2
  @rolling_query_max_memory_bytes 1024 * 1024 * 1024

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
      {:rolling, size} -> {:rolling, recent_runs_column(monitor_type), size}
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

  # The rolling fast path reads `test_case_runs_recent_100_per_case`. It
  # maintains `groupArraySorted` aggregates per `(project_id, test_case_id)`:
  # `recent_runs` holds
  # `(-ran_at_microseconds, is_flaky)` tuples for flakiness/count monitors and
  # `recent_successful_runs` holds `(-ran_at_microseconds, is_success)` tuples
  # for reliability monitors.
  #
  # The materialized-view scan is bounded by `active_test_cases_in_project`
  # rather than total run volume — usually a few thousand rows. The bucket
  # aggregate is `groupArraySorted` by `-ran_at_microseconds`, so the merged
  # array is already latest-first before the final user-configured slice.
  #
  # `test_case_runs` is a ReplacingMergeTree and flaky detection re-inserts a
  # run to set `is_flaky` after ingestion, so the materialized view can absorb
  # the same logical run several times. Those duplicates concentrate on
  # flaky/failed runs — a passing run is never re-marked — so counting raw
  # array entries inflates flakiness and deflates reliability for exactly the
  # runs a threshold reacts to.
  # `rolling_triggered_test_case_ids_from_recent_runs` collapses the array to
  # one row per run (keyed on `ran_at`) before computing a rate.
  #
  # `monitor_type`, `comparison`, `table`, `ordered_runs_expr`, and
  # `deduplicated_runs_expr` are interpolated because they are chosen from
  # fixed in-module allowlists (or are validated integers via `size`), so there
  # is no query-injection vector. `project_id` and `threshold` flow through
  # bound parameters.
  defp rolling_triggered_test_case_ids(project_id, monitor_type, size, threshold, comparison, test_case_ids) do
    source = recent_runs_source(recent_runs_column(monitor_type), size)

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

  defp rolling_measurements_from_recent_runs(
         {table, ordered_runs_expr, duplicate_position},
         project_id,
         size,
         test_case_ids
       ) do
    deduplicated_runs_expr = deduplicated_runs_expr(duplicate_position)

    sql = """
    SELECT
      test_case_id,
      arraySum(entry -> tupleElement(entry, 2), recent_runs) AS matching_run_count,
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
    WHERE length(recent_runs) > 0
    SETTINGS max_threads = #{@rolling_query_max_threads},
             max_memory_usage = #{@rolling_query_max_memory_bytes}
    """

    %{rows: rows} =
      ClickHouseRepo.query!(sql, %{
        project_id: project_id,
        test_case_ids: test_case_ids
      })

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
  defp recent_runs_column("reliability_rate"), do: "recent_successful_runs"
  defp recent_runs_column(_monitor_type), do: "recent_runs"

  # Returns `{table, ordered_runs_expr, duplicate_position}`.
  # `ordered_runs_expr` merges the full per-test-case aggregate in latest-first
  # order. The bucket stores `-ran_at_microseconds` in sorted state, so the
  # reader only needs a linear pass to collapse duplicates.
  #
  # The bucket is chosen strictly larger than the window (`size < bucket`) so
  # de-dup has some headroom: a bucket only holds `bucket` physical rows, and
  # re-inserted runs consume slots, so a window equal to the bucket can yield
  # fewer than `size` distinct runs after de-dup. The writer-side idempotency
  # work tracked in issue 12038 will make that headroom exact. Until then,
  # windows above the active bucket are rejected before a stale retired table
  # can be read.
  defp recent_runs_source(_column, size) when size > @max_active_rolling_window_size do
    raise ArgumentError,
          "rolling trigger windows must be at most #{@max_active_rolling_window_size} while aggregate storage is being replaced"
  end

  defp recent_runs_source(column, _size) do
    {
      "test_case_runs_recent_#{@active_recent_runs_bucket_size}_per_case",
      "groupArraySortedMerge(#{@active_recent_runs_bucket_size})(#{column})",
      :last
    }
  end

  defp rolling_triggered_test_case_ids_from_recent_runs(
         {table, ordered_runs_expr, duplicate_position},
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

    deduplicated_runs_expr = deduplicated_runs_expr(duplicate_position)

    # Collapse the bounded per-test-case array to one tuple per run
    # (`run_key` is the run's `ran_at` in microseconds), keeping `max(flag)` so
    # a run that was ever re-marked flaky / ever succeeded is represented once
    # with the right flag. Then keep the latest `size` distinct runs and compute
    # the rate over those, so a re-inserted run can no longer be counted more
    # than once. Keeping the work inside arrays avoids the expensive
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
    WHERE length(recent_runs) > 0
      AND #{rolling_having_expr(monitor_type)} #{rolling_comparison_op(comparison)} {threshold:Float64}
    SETTINGS max_threads = #{@rolling_query_max_threads},
             max_memory_usage = #{@rolling_query_max_memory_bytes}
    """

    params = maybe_put_test_case_ids(%{project_id: project_id, threshold: threshold * 1.0}, test_case_ids)

    # Raise on ClickHouse errors instead of swallowing them. If the materialized
    # view is missing or the query fails transiently, returning `[]` would tell
    # the worker "no test cases match" and trip recovery actions on every
    # active event. Letting the error propagate matches the
    # `ClickHouseRepo.all` path in the `last_days` branch and gives Oban a
    # chance to retry.
    %{rows: rows} = ClickHouseRepo.query!(sql, params)

    # ClickHouse returns identifier columns as 16-byte binaries here; the rest
    # of the worker compares against string-encoded identifiers from the Ecto
    # path, so normalise.
    Enum.map(rows, fn [binary] -> Ecto.UUID.load!(binary) end)
  end

  # Bucket states are sorted by `(-timestamp, flag)` ascending. Runs
  # are newest-first, duplicate timestamps are adjacent, and the largest flag
  # is last. Comparing every tuple's key with the next tuple's key keeps that
  # last tuple in a linear pass. The positive sentinel cannot collide with the
  # negative timestamp keys stored in the buckets.
  defp deduplicated_runs_expr(:last) do
    """
    arrayFilter(
      (entry, next_entry) -> tupleElement(entry, 1) != tupleElement(next_entry, 1),
      ordered_runs,
      arrayShiftLeft(
        ordered_runs,
        1,
        (toInt64(9223372036854775807), toUInt8(0))
      )
    )
    """
  end

  defp rolling_having_expr("flakiness_rate"),
    do: "arraySum(entry -> tupleElement(entry, 2), recent_runs) * 100.0 / length(recent_runs)"

  defp rolling_having_expr("flaky_run_count"), do: "arraySum(entry -> tupleElement(entry, 2), recent_runs)"

  defp rolling_having_expr("reliability_rate"),
    do: "arraySum(entry -> tupleElement(entry, 2), recent_runs) * 100.0 / length(recent_runs)"

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
