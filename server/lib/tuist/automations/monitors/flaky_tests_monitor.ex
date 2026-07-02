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

  The `rolling` mode reads bucketed `test_case_runs_recent_N_per_case`
  `AggregatingMergeTree` MVs for common windows and falls back to
  `test_case_runs_recent_per_case` for windows above the largest bucket. The
  buckets carry both a flaky aggregate (`recent_runs`) and a success aggregate
  (`recent_successful_runs`), so flakiness, flaky-run-count, and reliability
  monitors all take the same bucketed fast path — reliability just reads the
  success column. A project's whole rolling-window scan becomes one row per
  active test case, regardless of run volume — reading raw `test_case_runs`
  for that pattern is unrunnable on busy projects.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
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

  # The rolling fast path reads `test_case_runs_recent_N_per_case`, where N is
  # the smallest bucket in `@recent_runs_bucket_sizes` that can satisfy the
  # configured window. These tables maintain `groupArraySorted` aggregates
  # per `(project_id, test_case_id)`: `recent_runs` holds
  # `(-ran_at_microseconds, is_flaky)` tuples for flakiness/count monitors and
  # `recent_successful_runs` holds `(-ran_at_microseconds, is_success)` tuples
  # for reliability monitors. The full `test_case_runs_recent_per_case`
  # aggregate keeps 1000 entries of both for windows above the largest bucket.
  #
  # The MV scan is bounded by `active_test_cases_in_project` rather than
  # total run volume — usually a few thousand rows. The bucket aggregate is
  # `groupArraySorted` by `-ran_at_microseconds`, so the merged array is
  # already latest-first before the final user-configured slice (no re-sort);
  # only the 1000-entry fallback keeps `groupArrayLast` order and has to
  # `arrayReverseSort` before slicing.
  #
  # `test_case_runs` is a ReplacingMergeTree and flaky detection re-inserts a
  # run to set `is_flaky` after ingestion, so the MV can absorb the same
  # logical run several times. Those duplicates concentrate on flaky/failed
  # runs — a passing run is never re-marked — so counting raw array entries
  # inflates flakiness and deflates reliability for exactly the runs a
  # threshold reacts to. `rolling_triggered_test_case_ids_from_recent_runs`
  # collapses the array to one row per run (keyed on `ran_at`) before
  # computing a rate.
  #
  # `monitor_type`, `comparison`, `table`, `recent_runs_expr`, and
  # `run_key_expr` are interpolated because they are chosen from fixed
  # in-module allowlists (or are validated integers via `size`), so there is
  # no SQL-injection vector. `project_id` and `threshold` flow through bound
  # parameters.
  defp rolling_triggered_test_case_ids(project_id, monitor_type, size, threshold, comparison, test_case_ids) do
    {table, recent_runs_expr, run_key_expr} = recent_runs_source(recent_runs_column(monitor_type), size)

    rolling_triggered_test_case_ids_from_recent_runs(
      table,
      recent_runs_expr,
      run_key_expr,
      project_id,
      monitor_type,
      size,
      threshold,
      comparison,
      test_case_ids
    )
  end

  # Reliability measures successful runs; flakiness and count measure flaky
  # runs. Both live as parallel `(sort_key, flag)` aggregates on the same
  # rolling-window tables, so the routing below is identical and only the
  # aggregate column differs.
  defp recent_runs_column("reliability_rate"), do: "recent_successful_runs"
  defp recent_runs_column(_monitor_type), do: "recent_runs"

  # Returns `{table, recent_runs_expr, run_key_expr}`. `recent_runs_expr`
  # merges the full per-test-case aggregate; the dedup and latest-`size` slice
  # happen downstream. `run_key_expr` maps a tuple's sort key back to a
  # "larger = more recent" number so both encodings order the same way: the
  # 1000-entry fallback stores `ran_at` directly, while the buckets store
  # `-ran_at_microseconds`.
  defp recent_runs_source(column, size) do
    case Enum.find(@recent_runs_bucket_sizes, &(size <= &1)) do
      nil ->
        {
          "test_case_runs_recent_per_case",
          "groupArrayLastMerge(#{@max_rolling_window_size})(#{column})",
          "toUnixTimestamp64Micro(tupleElement(entry, 1))"
        }

      bucket_size ->
        {
          "test_case_runs_recent_#{bucket_size}_per_case",
          "groupArraySortedMerge(#{bucket_size})(#{column})",
          "-tupleElement(entry, 1)"
        }
    end
  end

  defp rolling_triggered_test_case_ids_from_recent_runs(
         table,
         recent_runs_expr,
         run_key_expr,
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

    # Expand the recent-runs array and collapse it to one row per run (keyed on
    # `run_key`, the run's `ran_at`), keeping `max(flag)` so a run that was ever
    # re-marked flaky / ever succeeded is represented once with the right flag.
    # Then keep the latest `size` distinct runs and compute the rate over those,
    # so a re-inserted run can no longer be counted more than once.
    sql = """
    SELECT test_case_id
    FROM (
      SELECT test_case_id, run_key, max(flag) AS flag
      FROM (
        SELECT
          test_case_id,
          #{run_key_expr} AS run_key,
          tupleElement(entry, 2) AS flag
        FROM (
          SELECT test_case_id, #{recent_runs_expr} AS recent_runs
          FROM #{table}
          WHERE project_id = {project_id:Int64}
            #{test_case_filter}
          GROUP BY test_case_id
        )
        ARRAY JOIN recent_runs AS entry
      )
      GROUP BY test_case_id, run_key
      ORDER BY run_key DESC
      LIMIT #{size} BY test_case_id
    )
    GROUP BY test_case_id
    HAVING #{rolling_having_expr(monitor_type)} #{rolling_comparison_op(comparison)} {threshold:Float64}
    """

    params = maybe_put_test_case_ids(%{project_id: project_id, threshold: threshold * 1.0}, test_case_ids)

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

  defp rolling_having_expr("flakiness_rate"), do: "sum(flag) * 100.0 / count()"

  defp rolling_having_expr("flaky_run_count"), do: "sum(flag)"

  defp rolling_having_expr("reliability_rate"), do: "sum(flag) * 100.0 / count()"

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
