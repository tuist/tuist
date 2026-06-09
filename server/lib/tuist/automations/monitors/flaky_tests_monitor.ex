defmodule Tuist.Automations.Monitors.FlakyTestsMonitor do
  @moduledoc """
  Evaluates flaky-test alerts.

  Each alert is parameterised by:

    * `monitor_type` — what's being measured (`flakiness_rate` or
      `flaky_run_count`)
    * `trigger_config.comparison` — how to compare the measurement to the
      threshold (`gte`, `gt`, `lt`, `lte`; defaults to `gte` for
      backward compatibility with detection alerts seeded before
      cleanup automations existed)
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

  The `rolling` mode reads bucketed `test_case_runs_recent_N_per_case`
  `AggregatingMergeTree` MVs for common windows and falls back to
  `test_case_runs_recent_per_case` for larger windows. A project's whole
  rolling-window scan becomes one row per active test case, regardless of run
  volume — reading raw `test_case_runs` for that pattern is unrunnable on busy
  projects.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRunDailyStatsPerCase

  @comparisons ~w(gte gt lt lte)

  # Product cap shared with `Alert.changeset/2`; larger values are rejected at
  # write time. Common windows use the smaller recent-runs MV fast path below.
  @max_rolling_window_size 1000
  @default_rolling_window_size 100
  @recent_runs_bucket_sizes [100, 250, 500, 750]

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

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled, test_case_ids)
    }
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

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled, test_case_ids)
    }
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

  # The rolling fast path reads `test_case_runs_recent_N_per_case`, where N is
  # the smallest bucket in `@recent_runs_bucket_sizes` that can satisfy the
  # configured window. These tables maintain `groupArraySorted` aggregates of
  # `(-ran_at_microseconds, is_flaky)` tuples per `(project_id, test_case_id)`.
  # The full `test_case_runs_recent_per_case` aggregate still keeps 1000
  # entries for larger user-configured windows, but common/default windows do
  # not have to deserialize that larger state.
  #
  # The MV scan is bounded by `active_test_cases_in_project` rather than
  # total run volume — usually a few thousand rows. The per-row aggregate is
  # sorted by `-ran_at_microseconds`, so the merged array is already
  # latest-first before the final user-configured slice.
  #
  # ReplacingMergeTree dedup on `test_case_runs` happens after the MV has
  # already absorbed the row, so a re-inserted run (e.g. is_flaky updated
  # later) appears twice in the bounded recent-runs array. That's bounded
  # noise — ≤1% at the default window — well within the natural variance
  # of a flakiness threshold.
  #
  # `monitor_type`, `comparison`, `table`, and `recent_n_expr` are
  # interpolated because they are chosen from fixed in-module allowlists, so
  # there is no SQL-injection vector. Numeric inputs (`project_id`, `size`,
  # `threshold`) flow through bound parameters.
  defp rolling_triggered_test_case_ids(project_id, monitor_type, size, threshold, comparison, test_case_ids) do
    {table, recent_n_expr} =
      case Enum.find(@recent_runs_bucket_sizes, &(size <= &1)) do
        nil ->
          {
            "test_case_runs_recent_per_case",
            """
            arraySlice(
              arrayReverseSort(x -> x.1, groupArrayLastMerge(#{@max_rolling_window_size})(recent_runs)),
              1,
              {size:UInt32}
            )
            """
          }

        bucket_size ->
          {
            "test_case_runs_recent_#{bucket_size}_per_case",
            """
            arraySlice(
              groupArraySortedMerge(#{bucket_size})(recent_runs),
              1,
              {size:UInt32}
            )
            """
          }
      end

    rolling_triggered_test_case_ids_from_recent_runs(
      table,
      recent_n_expr,
      project_id,
      monitor_type,
      size,
      threshold,
      comparison,
      test_case_ids
    )
  end

  defp rolling_triggered_test_case_ids_from_recent_runs(
         table,
         recent_n_expr,
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
        #{recent_n_expr} AS recent_n
      FROM #{table}
      WHERE project_id = {project_id:Int64}
        #{test_case_filter}
      GROUP BY test_case_id
    )
    WHERE length(recent_n) > 0
      AND #{rolling_having_expr(monitor_type)} #{rolling_comparison_op(comparison)} {threshold:Float64}
    """

    params = maybe_put_test_case_ids(%{project_id: project_id, size: size, threshold: threshold * 1.0}, test_case_ids)

    # Raise on ClickHouse errors instead of swallowing them. If the MV is
    # missing or the query fails transiently, returning `[]` would tell the
    # worker "no test cases match" and trip recovery actions on every active
    # event. Letting the error propagate matches the `ClickHouseRepo.all`
    # path in the `last_days` branch and gives Oban a chance to retry.
    %{rows: rows} = ClickHouseRepo.query!(sql, params)

    # ClickHouse returns UUID columns as 16-byte binaries here; the rest of
    # the worker compares against string-encoded UUIDs from the Ecto path,
    # so normalise.
    Enum.map(rows, fn [binary] -> Ecto.UUID.load!(binary) end)
  end

  defp rolling_having_expr("flakiness_rate"), do: "arraySum(x -> toFloat64(x.2), recent_n) * 100.0 / length(recent_n)"

  defp rolling_having_expr("flaky_run_count"), do: "arraySum(x -> toFloat64(x.2), recent_n)"

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

  defp load_all_test_case_ids(_project_id, false, _test_case_ids), do: []

  defp load_all_test_case_ids(_project_id, _recovery_enabled, test_case_ids) when is_list(test_case_ids) do
    test_case_ids
  end

  # `project_id` is the leading sort key; `DISTINCT` on `id` collapses
  # duplicate row versions from unmerged parts cheaply, avoiding the
  # multi-part full-row merge `FINAL` would force.
  defp load_all_test_case_ids(project_id, _recovery_enabled, _test_case_ids) do
    ClickHouseRepo.all(
      from(tc in TestCase,
        where: tc.project_id == ^project_id,
        distinct: true,
        select: tc.id
      )
    )
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
  # it as the fallback so existing alerts don't change behaviour.
  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"
end
