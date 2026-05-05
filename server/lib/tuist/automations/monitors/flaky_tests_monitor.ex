defmodule Tuist.Automations.Monitors.FlakyTestsMonitor do
  @moduledoc false
  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Tests
  alias Tuist.Tests.FlakyTestCaseRun
  alias Tuist.Tests.TestCase
  alias Tuist.Tests.TestCaseRun

  def evaluate(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 10
    window = parse_window(trigger_config["window"] || "30d")
    project_id = alert.project_id

    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    # Step 1: find test cases that had at least one flaky run (narrows the scan).
    # Served by the `flaky_test_case_runs` MV — ordered by
    # (project_id, ran_at, test_case_id), so this is a small prefix scan.
    candidate_ids = flaky_candidate_ids(project_id, cutoff)

    # Step 2: compute rate only for candidates, filter by threshold in
    # ClickHouse. Hits the main table because we need non-flaky runs to
    # compute the denominator. The `test_case_id in (candidates)` clause
    # aligns with the main table's sort prefix `(project_id, test_case_id)`.
    triggered_test_case_ids =
      if Enum.any?(candidate_ids) do
        ClickHouseRepo.all(
          from(tcr in TestCaseRun,
            where: tcr.project_id == ^project_id,
            where: tcr.inserted_at >= ^cutoff,
            where: tcr.test_case_id in ^candidate_ids,
            group_by: tcr.test_case_id,
            having: fragment("countIf(?) * 100.0 / count() >= ?", tcr.is_flaky, ^threshold),
            select: tcr.test_case_id
          )
        )
      else
        []
      end

    all_test_case_ids = load_all_test_case_ids(project_id, alert.recovery_enabled)

    %{
      triggered: triggered_test_case_ids,
      all: all_test_case_ids
    }
  end

  def evaluate_by_run_count(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 1
    window = parse_window(trigger_config["window"] || "30d")
    project_id = alert.project_id

    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    # Served by the `flaky_test_case_runs` MV — it only stores flaky rows and
    # is ordered by (project_id, ran_at, test_case_id), so both the
    # project_id + ran_at prefix scan and the group-by are efficient.
    triggered_test_case_ids =
      ClickHouseRepo.all(
        from(tcr in FlakyTestCaseRun,
          where: tcr.project_id == ^project_id,
          where: tcr.ran_at >= ^cutoff,
          group_by: tcr.test_case_id,
          having: count() >= ^threshold,
          select: tcr.test_case_id
        )
      )

    all_test_case_ids = load_all_test_case_ids(project_id, alert.recovery_enabled)

    %{
      triggered: triggered_test_case_ids,
      all: all_test_case_ids
    }
  end

  @doc """
  Inverse of `evaluate_by_run_count/1`. Fires for tests that are currently
  flagged (`is_flaky = true`) but accumulated fewer than `threshold` flaky
  runs in the trigger window. Intended for cleanup automations that unflag
  stale labels — including ones set manually or by a deleted automation —
  without coupling them to any other alert's recovery state.

  Returns the same shape as the other evaluators so the worker can dispatch
  it the same way.
  """
  def evaluate_by_run_count_below(alert) do
    trigger_config = alert.trigger_config
    threshold = trigger_config["threshold"] || 1
    window = parse_window(trigger_config["window"] || "30d")
    project_id = alert.project_id

    cutoff = DateTime.add(DateTime.utc_now(), -window, :second)

    flagged_ids = Tests.list_flagged_flaky_test_case_ids(project_id)

    triggered_test_case_ids =
      if Enum.any?(flagged_ids) do
        # Count flaky runs per flagged test inside the window. The MV doesn't
        # materialise rows for tests with zero flaky runs, so missing ids in
        # the result are treated as count = 0.
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

        Enum.filter(flagged_ids, fn id -> Map.get(counts, id, 0) < threshold end)
      else
        []
      end

    all_test_case_ids = load_all_test_case_ids(project_id, alert.recovery_enabled)

    %{
      triggered: triggered_test_case_ids,
      all: all_test_case_ids
    }
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
end
