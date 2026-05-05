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
  """
  import Ecto.Query

  alias Tuist.ClickHouseRepo
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

    triggered_test_case_ids = ClickHouseRepo.all(flakiness_rate_query(project_id, cutoff, threshold, comparison))

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

    triggered_test_case_ids = ClickHouseRepo.all(flaky_run_count_query(project_id, cutoff, threshold, comparison))

    %{
      triggered: triggered_test_case_ids,
      all: load_all_test_case_ids(project_id, alert.recovery_enabled)
    }
  end

  # Ecto's `fragment(...)` macro requires a literal first argument to prevent
  # SQL-injection routes, so each comparison gets its own clause instead of an
  # interpolated operator.
  defp flakiness_rate_query(project_id, cutoff, threshold, "gte") do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() >= ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flakiness_rate_query(project_id, cutoff, threshold, "gt") do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() > ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flakiness_rate_query(project_id, cutoff, threshold, "lt") do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() < ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flakiness_rate_query(project_id, cutoff, threshold, "lte") do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) * 100.0 / count() <= ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  # `gte` / `gt` reach for the `flaky_test_case_runs` MV because it stores
  # only flaky rows and is keyed on `(project_id, ran_at, test_case_id)` —
  # cheap aggregate. `lt` / `lte` need the zero-flaky-runs case too, so they
  # have to scan `test_case_runs` and `countIf` flakiness directly.
  defp flaky_run_count_query(project_id, cutoff, threshold, "gte") do
    from(tcr in FlakyTestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.ran_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("count() >= ?", ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flaky_run_count_query(project_id, cutoff, threshold, "gt") do
    from(tcr in FlakyTestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.ran_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("count() > ?", ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flaky_run_count_query(project_id, cutoff, threshold, "lt") do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) < ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
    )
  end

  defp flaky_run_count_query(project_id, cutoff, threshold, "lte") do
    from(tcr in TestCaseRun,
      where: tcr.project_id == ^project_id,
      where: tcr.inserted_at >= ^cutoff,
      group_by: tcr.test_case_id,
      having: fragment("countIf(?) <= ?", tcr.is_flaky, ^threshold),
      select: tcr.test_case_id
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

  # Kept so other callers / future tests can branch on direction without
  # re-deriving the set.
  def below_comparison?(comparison), do: comparison in @below_comparisons
end
