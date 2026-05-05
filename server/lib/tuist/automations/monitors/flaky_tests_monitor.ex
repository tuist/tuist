defmodule Tuist.Automations.Monitors.FlakyTestsMonitor do
  @moduledoc """
  Evaluates flaky-test alerts. Each alert is parameterised by:

    * `monitor_type` — what's being measured (`flakiness_rate` or
      `flaky_run_count`)
    * `trigger_config.comparison` — how to compare the measurement to the
      threshold (`gte`, `gt`, `lt`, `lte`; defaults to `gte` for
      backward compatibility with detection alerts seeded before
      cleanup automations existed)

  The comparison direction also implicitly scopes the candidate set:

    * `gte` / `gt` (detection): every test with runs in the window. The
      action typically marks tests as flaky.
    * `lt` / `lte` (cleanup): only tests already flagged
      (`is_flaky = true`); tests with no runs in the window are treated as
      below threshold ("no recent activity" is the strongest signal a stale
      mark should be cleared).
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests
  alias Tuist.Tests.FlakyTestCaseRun
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun

  @comparisons ~w(gte gt lt lte)
  @below_comparisons ~w(lt lte)

  def evaluate(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    window = parse_window(trigger_config["window"] || "30d")
    comparison = parse_comparison(trigger_config["comparison"])
    project_id = alert.project_id

    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    triggered_test_case_ids = evaluate_flakiness_rate(project_id, cutoff, threshold, comparison)

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

    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    triggered_test_case_ids = evaluate_flaky_run_count(project_id, cutoff, threshold, comparison)

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled)
    }
  end

  defp evaluate_flakiness_rate(project_id, cutoff, threshold, comparison) when comparison in @below_comparisons do
    flagged_ids = Tests.list_flagged_flaky_test_case_ids(project_id)

    if Enum.any?(flagged_ids) do
      with_runs_below =
        ClickHouseRepo.all(flakiness_rate_query(project_id, cutoff, threshold, comparison, flagged_ids))

      # Tests with no runs in the window have an undefined rate; treat them as
      # below the threshold (no recent activity → stale flaky mark).
      with_any_runs =
        ClickHouseRepo.all(
          from(tcr in TestCaseRun,
            where: tcr.project_id == ^project_id,
            where: tcr.inserted_at >= ^cutoff,
            where: tcr.test_case_id in ^flagged_ids,
            select: tcr.test_case_id,
            distinct: true
          )
        )

      without_any_runs = MapSet.difference(MapSet.new(flagged_ids), MapSet.new(with_any_runs))

      Enum.uniq(with_runs_below ++ MapSet.to_list(without_any_runs))
    else
      []
    end
  end

  defp evaluate_flakiness_rate(project_id, cutoff, threshold, comparison) do
    # Step 1: find test cases that had at least one flaky run in the window.
    # Served by the `flaky_test_case_runs` MV (project_id, ran_at, test_case_id),
    # so this is a small prefix scan.
    candidate_ids = flaky_candidate_ids(project_id, cutoff)

    if Enum.any?(candidate_ids) do
      # Step 2: compute rate only for candidates, filter by threshold in
      # ClickHouse. Hits the main table because we need non-flaky runs to
      # compute the denominator. The `test_case_id in (candidates)` clause
      # aligns with the main table's sort prefix `(project_id, test_case_id)`.
      ClickHouseRepo.all(flakiness_rate_query(project_id, cutoff, threshold, comparison, candidate_ids))
    else
      []
    end
  end

  # Ecto's `fragment(...)` macro requires a literal first argument to prevent
  # SQL-injection routes, so each comparison gets its own clause instead of an
  # interpolated operator.
  defp flakiness_rate_query(project_id, cutoff, threshold, "gte", scope_ids) do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      where: tcr.test_case_id in ^scope_ids,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() >= ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flakiness_rate_query(project_id, cutoff, threshold, "gt", scope_ids) do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      where: tcr.test_case_id in ^scope_ids,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() > ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flakiness_rate_query(project_id, cutoff, threshold, "lt", scope_ids) do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      where: tcr.test_case_id in ^scope_ids,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() < ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flakiness_rate_query(project_id, cutoff, threshold, "lte", scope_ids) do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      where: tcr.test_case_id in ^scope_ids,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() <= ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp evaluate_flaky_run_count(project_id, cutoff, threshold, comparison) when comparison in @below_comparisons do
    flagged_ids = Tests.list_flagged_flaky_test_case_ids(project_id)

    if Enum.any?(flagged_ids) do
      counts =
        from(tcr in FlakyTestCaseRun,
          where: tcr.project_id == ^project_id,
          where: tcr.ran_at >= ^cutoff,
          where: tcr.test_case_id in ^flagged_ids,
          group_by: tcr.test_case_id,
          select: {tcr.test_case_id, count()}
        )
        |> ClickHouseRepo.all()
        |> Map.new()

      compare = compare_fun(comparison)
      Enum.filter(flagged_ids, fn id -> compare.(Map.get(counts, id, 0), threshold) end)
    else
      []
    end
  end

  defp evaluate_flaky_run_count(project_id, cutoff, threshold, "gte") do
    ClickHouseRepo.all(
      from(tcr in FlakyTestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.ran_at >= ^cutoff,
        group_by: tcr.test_case_id,
        having: fragment("count() >= ?", ^threshold),
        select: tcr.test_case_id
      )
    )
  end

  defp evaluate_flaky_run_count(project_id, cutoff, threshold, "gt") do
    ClickHouseRepo.all(
      from(tcr in FlakyTestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.ran_at >= ^cutoff,
        group_by: tcr.test_case_id,
        having: fragment("count() > ?", ^threshold),
        select: tcr.test_case_id
      )
    )
  end

  defp flaky_candidate_ids(project_id, cutoff) do
    ClickHouseRepo.all(
      from(tcr in FlakyTestCaseRun,
        where: tcr.project_id == ^project_id,
        where: tcr.ran_at >= ^cutoff,
        select: tcr.test_case_id,
        distinct: true
      )
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

  defp parse_window(window) when is_binary(window) do
    case Integer.parse(window) do
      {value, "d"} -> value * 86_400
      {value, "h"} -> value * 3600
      {value, "m"} -> value * 60
      _ -> 30 * 86_400
    end
  end

  defp parse_window(_), do: 30 * 86_400

  # `gte` is the historical default before alerts had a comparison field; keep
  # it as the fallback so existing alerts don't change behaviour.
  defp parse_comparison(comparison) when comparison in @comparisons, do: comparison
  defp parse_comparison(_), do: "gte"

  # Used only for the `lt` / `lte` flaky_run_count path, where the comparison
  # runs in Elixir against a {test_case_id, count} map (so missing ids — tests
  # with no flaky runs — get treated as count = 0).
  defp compare_fun("lt"), do: &</2
  defp compare_fun("lte"), do: &<=/2
end
