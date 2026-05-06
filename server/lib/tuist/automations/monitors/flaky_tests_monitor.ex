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

  The candidate set is always "test cases with at least one run in the
  window." Tests with no runs are excluded because they have nothing to
  measure. Whether a test case enters or leaves the matching set drives
  the worker's transition logic — this module just reports the current
  match; the worker silences the initial baseline so users don't get
  flooded for the established state.

  All four comparison directions read the
  `test_case_run_daily_stats_per_case` AggregatingMergeTree, ordered by
  `(project_id, date, test_case_id)`. A 30-day evaluation reads ~30 rows
  per test case for the project — bounded prefix scan rather than a
  full-table walk on `test_case_runs` (which is keyed on
  `(test_run_id, …)` and would have to filter `project_id` after reading
  every granule in the relevant monthly partitions).
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRunDailyStatsPerCase

  @comparisons ~w(gte gt lt lte)

  def evaluate(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    window = parse_window(trigger_config["window"] || "30d")
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    cutoff_date = window_cutoff_date(window)

    triggered_test_case_ids =
      ClickHouseRepo.all(flakiness_rate_query(project_id, cutoff_date, threshold, comparison))

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled)
    }
  end

  def evaluate_by_run_count(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 1
    window = parse_window(trigger_config["window"] || "30d")
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    cutoff_date = window_cutoff_date(window)

    triggered_test_case_ids =
      ClickHouseRepo.all(flaky_run_count_query(project_id, cutoff_date, threshold, comparison))

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled)
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
  defp flakiness_rate_query(project_id, cutoff_date, threshold, "gte") do
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

  defp flakiness_rate_query(project_id, cutoff_date, threshold, "gt") do
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

  defp flakiness_rate_query(project_id, cutoff_date, threshold, "lt") do
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

  defp flakiness_rate_query(project_id, cutoff_date, threshold, "lte") do
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

  defp flaky_run_count_query(project_id, cutoff_date, threshold, "gte") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) >= ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_query(project_id, cutoff_date, threshold, "gt") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) > ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_query(project_id, cutoff_date, threshold, "lt") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) < ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp flaky_run_count_query(project_id, cutoff_date, threshold, "lte") do
    from(daily in TestCaseRunDailyStatsPerCase,
      where: daily.project_id == ^project_id,
      where: daily.date >= ^cutoff_date,
      group_by: daily.test_case_id,
      having: fragment("sumMerge(flaky_run_count) <= ?", ^threshold),
      select: daily.test_case_id
    )
  end

  defp load_all_test_case_ids(_project_id, false), do: []

  # `project_id` is the leading sort key; `DISTINCT` on `id` collapses
  # duplicate row versions from unmerged parts cheaply, avoiding the
  # multi-part full-row merge `FINAL` would force.
  defp load_all_test_case_ids(project_id, _recovery_enabled) do
    ClickHouseRepo.all(
      from(tc in TestCase,
        where: tc.project_id == ^project_id,
        distinct: true,
        select: tc.id
      )
    )
  end

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

  # `gte` is the historical default before alerts had a comparison field; keep
  # it as the fallback so existing alerts don't change behaviour.
  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"
end
