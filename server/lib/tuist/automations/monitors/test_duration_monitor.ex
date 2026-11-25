defmodule Tuist.Automations.Monitors.TestDurationMonitor do
  @moduledoc """
  Evaluates `test_duration` alerts: test cases whose average, median, 90th or
  99th percentile run duration over a calendar window compares against a
  threshold in milliseconds.

  It reads `test_case_duration_daily_stats_per_case`, the same aggregate the
  Test Cases table shows durations from, merged across CI and local runs on
  every branch, so a matching test case is one the table would show at or
  above the threshold for the same window.

  A test case needs at least five runs in the window to be measured, the floor
  the Test Cases table applies before it shows or ranks durations. Below it the
  test case is neither triggered nor counted as recovered.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCaseDurationDailyStatsPerCase

  @min_samples 5
  @query_settings [optimize_aggregation_in_order: 1]

  def evaluate(alert, test_case_ids \\ nil) do
    config = alert.trigger_config
    value = statistic(config["statistic"])
    threshold = config["threshold"]

    triggered =
      alert
      |> measured_query(test_case_ids)
      |> having(^comparison(config["comparison"], value, threshold))
      |> ClickHouseRepo.all(settings: @query_settings)

    %{triggered: triggered}
  end

  @doc """
  The subset of `test_case_ids` with enough runs in the alert's window to be
  measured, so recovery does not read a test case that stopped running as one
  that got faster.
  """
  def measurable_test_case_ids(_alert, []), do: []

  def measurable_test_case_ids(alert, test_case_ids) do
    alert
    |> measured_query(test_case_ids)
    |> ClickHouseRepo.all(settings: @query_settings)
  end

  defp measured_query(alert, test_case_ids) do
    filter_test_case_ids(
      from(stats in TestCaseDurationDailyStatsPerCase,
        where: stats.project_id == ^alert.project_id,
        where: stats.date >= ^window_cutoff_date(alert.trigger_config["window"]),
        group_by: stats.test_case_id,
        having: fragment("uniqExactMerge(run_count) >= ?", ^@min_samples),
        select: stats.test_case_id
      ),
      test_case_ids
    )
  end

  defp filter_test_case_ids(query, nil), do: query
  defp filter_test_case_ids(query, []), do: where(query, false)

  defp filter_test_case_ids(query, test_case_ids) do
    where(query, [stats], fragment("? IN (?)", stats.test_case_id, type(^test_case_ids, {:array, Ecto.UUID})))
  end

  # A fragment takes its SQL at compile time, so each statistic is its own clause.
  defp statistic("p50"), do: dynamic(fragment("quantileMerge(0.5)(p50_duration)"))
  defp statistic("p90"), do: dynamic(fragment("quantileMerge(0.9)(p90_duration)"))
  defp statistic("p99"), do: dynamic(fragment("quantileMerge(0.99)(p99_duration)"))
  defp statistic(_average), do: dynamic(fragment("avgMerge(avg_duration)"))

  defp comparison("gt", value, threshold), do: dynamic(^value > ^threshold)
  defp comparison("lt", value, threshold), do: dynamic(^value < ^threshold)
  defp comparison("lte", value, threshold), do: dynamic(^value <= ^threshold)
  defp comparison(_gte, value, threshold), do: dynamic(^value >= ^threshold)

  # `Alert.changeset/2` only accepts day-level windows (`Nd`). The aggregate is
  # per day, so the cutoff is the start of the first day in the window.
  defp window_cutoff_date(window) do
    days =
      case Integer.parse(to_string(window)) do
        {value, "d"} when value > 0 -> value
        _ -> 30
      end

    Date.add(Date.utc_today(), -days)
  end
end
