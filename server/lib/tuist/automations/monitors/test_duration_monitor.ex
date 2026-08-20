defmodule Tuist.Automations.Monitors.TestDurationMonitor do
  @moduledoc """
  Evaluates test-duration alerts.

  An alert is parameterised by:

    * `trigger_config.percentile` — which statistic to measure (`p50`, `p90`,
      `p99`, or `avg`; defaults to `p90`)
    * `trigger_config.threshold` — the duration in milliseconds to compare
      against
    * `trigger_config.comparison` — `gte`, `gt`, `lt`, or `lte`; defaults to
      `gte`, the direction that answers "which tests got slow"
    * `trigger_config.window` — the calendar window, as `"Nd"`
    * `trigger_config.environment` — `any`, `ci`, or `local`

  Measurements come from `test_case_duration_daily_stats_per_case`, the same
  aggregate the Test Cases listing reads, so an alert and the dashboard row it
  points at cannot disagree about how long a test takes. `is_ci` is part of
  that table's sort key, which is what makes "only alert on CI" a narrower read
  rather than a filter applied after the fact.

  There is no rolling-window mode. The rolling aggregates
  (`test_case_runs_recent_per_case`) store `(ran_at, UInt8)` tuples — a flag
  per run — so they can carry flakiness and success but not a duration. A
  calendar window is also the better fit for the question: "slow over the last
  week" is answerable, "slow across the last 50 runs whenever they happened"
  is not, because those runs may span an afternoon or a quarter.

  ## The sample floor

  A percentile over a handful of runs is not a percentile. Test cases with
  fewer than `Tuist.Tests.min_duration_samples/0` runs in the window are
  excluded rather than compared against the threshold, matching the floor the
  listing uses to decide whether to show a duration at all. Without it, a test
  that ran twice — once during a debugger pause — would page someone on the
  strength of a single observation, which is the exact failure the duration
  work exists to remove.

  The floor is applied to `uniqExactMerge(run_count)`, a distinct count over
  run ids rather than a row count, because a flaky-state correction re-inserts
  a run and reaches the aggregate twice. Counting rows would let three real
  runs plus two corrections pass for five.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests
  alias Tuist.Tests.TestCaseDurationDailyStatsPerCase

  @comparisons ~w(gte gt lt lte)
  @percentiles ~w(p50 p90 p99 avg)

  @default_percentile "p90"
  @default_window_days 30

  def percentiles, do: @percentiles

  def evaluate(alert, test_case_ids \\ nil) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"]
    percentile = parse_percentile(trigger_config["percentile"])
    comparison = parse_comparison(trigger_config["comparison"])

    triggered_test_case_ids =
      alert.project_id
      |> duration_query(
        window_cutoff_date(trigger_config["window"]),
        percentile,
        threshold,
        comparison,
        environment(trigger_config["environment"])
      )
      |> filter_test_case_ids(test_case_ids)
      |> ClickHouseRepo.all()

    %{triggered: triggered_test_case_ids}
  end

  defp duration_query(project_id, cutoff_date, percentile, threshold, comparison, is_ci) do
    metric = duration_merge_dynamic(percentile)

    apply_environment_filter(
      from(stats in TestCaseDurationDailyStatsPerCase,
        where: stats.project_id == ^project_id,
        where: stats.date >= ^cutoff_date,
        group_by: stats.test_case_id,
        having: ^sample_floor_dynamic(),
        having: ^threshold_dynamic(metric, comparison, threshold),
        select: stats.test_case_id
      ),
      is_ci
    )
  end

  defp apply_environment_filter(query, nil), do: query

  defp apply_environment_filter(query, is_ci), do: where(query, [stats], stats.is_ci == ^is_ci)

  defp sample_floor_dynamic do
    dynamic(fragment("uniqExactMerge(run_count) >= ?", ^Tests.min_duration_samples()))
  end

  # One clause per statistic rather than an interpolated expression: `fragment`
  # takes its SQL at compile time. Mirrors `Tuist.Tests`' merges so an alert
  # and the listing read the same number out of the same states.
  defp duration_merge_dynamic("p50"), do: dynamic(fragment("round(quantileMerge(0.5)(p50_duration))"))

  defp duration_merge_dynamic("p90"), do: dynamic(fragment("round(quantileMerge(0.9)(p90_duration))"))

  defp duration_merge_dynamic("p99"), do: dynamic(fragment("round(quantileMerge(0.99)(p99_duration))"))

  defp duration_merge_dynamic("avg"), do: dynamic(fragment("round(avgMerge(avg_duration))"))

  defp threshold_dynamic(metric, "gte", threshold), do: dynamic(^metric >= ^threshold)
  defp threshold_dynamic(metric, "gt", threshold), do: dynamic(^metric > ^threshold)
  defp threshold_dynamic(metric, "lt", threshold), do: dynamic(^metric < ^threshold)
  defp threshold_dynamic(metric, "lte", threshold), do: dynamic(^metric <= ^threshold)

  defp filter_test_case_ids(query, nil), do: query

  defp filter_test_case_ids(query, test_case_ids), do: where(query, [stats], stats.test_case_id in ^test_case_ids)

  # `nil` means "any environment" and leaves the read unfiltered. Anything
  # unrecognised is treated the same way rather than silently narrowing to one
  # environment, which would make an alert quietly stop matching.
  defp environment("ci"), do: true
  defp environment("local"), do: false
  defp environment(_), do: nil

  # `Alert.changeset/2` constrains the window to `Nd`, so only day-suffixed
  # strings need handling here. Anything else falls back to the default for
  # legacy or hand-written config.
  defp window_cutoff_date(window) do
    Date.add(Date.utc_today(), -window_days(window))
  end

  defp window_days(window) when is_binary(window) do
    case Integer.parse(window) do
      {value, "d"} when value > 0 -> value
      _ -> @default_window_days
    end
  end

  defp window_days(_), do: @default_window_days

  defp parse_percentile(percentile) when percentile in @percentiles, do: percentile
  defp parse_percentile(_), do: @default_percentile

  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"
end
