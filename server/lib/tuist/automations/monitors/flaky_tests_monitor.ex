defmodule Tuist.Automations.Monitors.FlakyTestsMonitor do
  @moduledoc false
  import Ecto.Query

  alias Tuist.ClickHouseRepo
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

  defp load_all_test_case_ids(project_id, _recovery_enabled) do
    ClickHouseRepo.all(from(tc in TestCase, hints: ["FINAL"], where: tc.project_id == ^project_id, select: tc.id))
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
