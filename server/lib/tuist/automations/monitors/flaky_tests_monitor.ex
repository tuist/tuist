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

  The `rolling` mode reads `test_case_runs_recent_per_case`, an
  `AggregatingMergeTree` MV that maintains a `groupArrayLast(N)` aggregate
  of `(ran_at, is_flaky)` tuples per `(project_id, test_case_id)`. A
  project's whole rolling-window scan becomes one row per active test
  case, regardless of run volume — reading raw `test_case_runs` for that
  pattern is unrunnable on busy projects.
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRunDailyStatsPerCase

  @comparisons ~w(gte gt lt lte)

  # Matches the `groupArrayLast(N)` cap baked into
  # `test_case_runs_recent_per_case_mv` and the `Alert.changeset/2`
  # validation. If we ever raise the user-facing cap, all three sites need to
  # move together.
  @max_rolling_window_size 1000

  def evaluate(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    triggered_test_case_ids =
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          ClickHouseRepo.all(
            flakiness_rate_last_days_query(project_id, window_cutoff_date(seconds), threshold, comparison)
          )

        {:rolling, size} ->
          rolling_triggered_test_case_ids(project_id, "flakiness_rate", size, threshold, comparison)
      end

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
      case window_mode(trigger_config) do
        {:last_days, seconds} ->
          ClickHouseRepo.all(
            flaky_run_count_last_days_query(project_id, window_cutoff_date(seconds), threshold, comparison)
          )

        {:rolling, size} ->
          rolling_triggered_test_case_ids(project_id, "flaky_run_count", size, threshold, comparison)
      end

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

  # The rolling path reads `test_case_runs_recent_per_case_mv`, which
  # maintains a `groupArrayLast` aggregate of `(ran_at, is_flaky)` tuples per
  # `(project_id, test_case_id)`, capped at `@max_rolling_window_size`
  # entries. Reading raw `test_case_runs` here doesn't scale: even with a
  # 30-day lookback and `LIMIT N BY`, the query has to walk every run in the
  # project's lookback (200M+ rows on busy projects) because the table's
  # primary key prefix doesn't fit "last N runs per test case per project."
  #
  # The MV scan is bounded by `active_test_cases_in_project` rather than
  # total run volume — usually a few thousand rows. We sort the per-row
  # array by `ran_at` DESC at read time so the user-facing semantic stays
  # exact "last N by ran_at" rather than "last N by insertion order."
  #
  # ReplacingMergeTree dedup on `test_case_runs` happens after the MV has
  # already absorbed the row, so a re-inserted run (e.g. is_flaky updated
  # later) appears twice in the `groupArrayLast` array. That's bounded
  # noise — ≤1% at the default window — well within the natural variance
  # of a flakiness threshold.
  #
  # `monitor_type` and `comparison` are interpolated because each is
  # constrained to a fixed allowlist, so there is no SQL-injection vector.
  # Numeric inputs (`project_id`, `size`, `threshold`) flow through bound
  # parameters.
  defp rolling_triggered_test_case_ids(project_id, monitor_type, size, threshold, comparison) do
    sql = """
    SELECT test_case_id
    FROM (
      SELECT
        test_case_id,
        arraySlice(
          arrayReverseSort(x -> x.1, groupArrayLastMerge(#{@max_rolling_window_size})(recent_runs)),
          1,
          {size:UInt32}
        ) AS recent_n
      FROM test_case_runs_recent_per_case
      WHERE project_id = {project_id:Int64}
      GROUP BY test_case_id
    )
    WHERE length(recent_n) > 0
      AND #{rolling_having_expr(monitor_type)} #{rolling_comparison_op(comparison)} {threshold:Float64}
    """

    case ClickHouseRepo.query(sql, %{project_id: project_id, size: size, threshold: threshold * 1.0}) do
      {:ok, %{rows: rows}} ->
        # ClickHouse returns UUID columns as 16-byte binaries here; the rest
        # of the worker compares against string-encoded UUIDs from the Ecto
        # path, so normalise.
        Enum.map(rows, fn [binary] -> Ecto.UUID.load!(binary) end)

      _ ->
        []
    end
  end

  defp rolling_having_expr("flakiness_rate"), do: "arraySum(x -> toFloat64(x.2), recent_n) * 100.0 / length(recent_n)"

  defp rolling_having_expr("flaky_run_count"), do: "arraySum(x -> toFloat64(x.2), recent_n)"

  defp rolling_comparison_op("gte"), do: ">="
  defp rolling_comparison_op("gt"), do: ">"
  defp rolling_comparison_op("lt"), do: "<"
  defp rolling_comparison_op("lte"), do: "<="

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

  defp parse_rolling_size(size) when is_integer(size) and size > 0, do: size
  defp parse_rolling_size(_), do: 100

  # `gte` is the historical default before alerts had a comparison field; keep
  # it as the fallback so existing alerts don't change behaviour.
  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"
end
