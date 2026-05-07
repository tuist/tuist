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

  The `rolling` mode reads `test_case_runs` directly with a
  `row_number() OVER (PARTITION BY test_case_id ORDER BY ran_at DESC)`
  so we can keep "last N runs per test case" without a per-day rollup.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun
  alias Tuist.Tests.TestCaseRunDailyStatsPerCase

  @comparisons ~w(gte gt lt lte)

  def evaluate(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    triggered_test_case_ids =
      ClickHouseRepo.all(flakiness_rate_query(project_id, threshold, comparison, trigger_config))

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled)
    }
  end

  def evaluate_by_run_count(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 1
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    triggered_test_case_ids =
      ClickHouseRepo.all(flaky_run_count_query(project_id, threshold, comparison, trigger_config))

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled)
    }
  end

  defp flakiness_rate_query(project_id, threshold, comparison, trigger_config) do
    case window_mode(trigger_config) do
      {:last_days, seconds} ->
        flakiness_rate_last_days_query(project_id, window_cutoff_date(seconds), threshold, comparison)

      {:rolling, size} ->
        flakiness_rate_rolling_query(project_id, size, threshold, comparison)
    end
  end

  defp flaky_run_count_query(project_id, threshold, comparison, trigger_config) do
    case window_mode(trigger_config) do
      {:last_days, seconds} ->
        flaky_run_count_last_days_query(project_id, window_cutoff_date(seconds), threshold, comparison)

      {:rolling, size} ->
        flaky_run_count_rolling_query(project_id, size, threshold, comparison)
    end
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

  defp flakiness_rate_rolling_query(project_id, size, threshold, "gte") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) * 100.0 / count(*) >= ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flakiness_rate_rolling_query(project_id, size, threshold, "gt") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) * 100.0 / count(*) > ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flakiness_rate_rolling_query(project_id, size, threshold, "lt") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) * 100.0 / count(*) < ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flakiness_rate_rolling_query(project_id, size, threshold, "lte") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) * 100.0 / count(*) <= ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flaky_run_count_rolling_query(project_id, size, threshold, "gte") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) >= ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flaky_run_count_rolling_query(project_id, size, threshold, "gt") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) > ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flaky_run_count_rolling_query(project_id, size, threshold, "lt") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) < ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  defp flaky_run_count_rolling_query(project_id, size, threshold, "lte") do
    from(t in subquery(rolling_window_runs(project_id, size)),
      group_by: t.test_case_id,
      having: fragment("sum(?) <= ?", t.is_flaky_int, ^threshold),
      select: t.test_case_id
    )
  end

  # `row_number() OVER (PARTITION BY test_case_id ORDER BY ran_at DESC)` so we
  # can keep the latest `size` runs per test case. The outer query that wraps
  # this filters by `rn <= size` and aggregates `is_flaky_int`.
  defp rolling_window_runs(project_id, size) do
    ranked =
      from(r in TestCaseRun,
        where: r.project_id == ^project_id,
        where: not is_nil(r.test_case_id),
        select: %{
          test_case_id: r.test_case_id,
          is_flaky_int: fragment("toUInt8(?)", r.is_flaky),
          rn: fragment("row_number() OVER (PARTITION BY ? ORDER BY ? DESC)", r.test_case_id, r.ran_at)
        }
      )

    from(t in subquery(ranked),
      where: t.rn <= ^size,
      select: %{test_case_id: t.test_case_id, is_flaky_int: t.is_flaky_int}
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

  defp window_mode(trigger_config) do
    case trigger_config["window_type"] do
      "rolling" -> {:rolling, parse_rolling_size(trigger_config["rolling_window_size"])}
      _ -> {:last_days, parse_window(trigger_config["window"] || "30d")}
    end
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

  defp parse_rolling_size(size) when is_integer(size) and size > 0, do: size
  defp parse_rolling_size(_), do: 100

  # `gte` is the historical default before alerts had a comparison field; keep
  # it as the fallback so existing alerts don't change behaviour.
  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"
end
