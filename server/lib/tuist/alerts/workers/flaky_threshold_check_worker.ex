defmodule Tuist.Alerts.Workers.FlakyThresholdCheckWorker do
  @moduledoc """
  A job that checks if test cases have reached the flaky threshold and marks them as flaky.

  This worker receives a batch of test_case_ids that have had a flaky run in a recent test.
  It checks each test case's flaky run count against the project's threshold and:
  - Marks test cases as flaky when they reach the threshold
  - Optionally auto-quarantines them if the project has that setting enabled
  - Enqueues FlakyTestAlertWorker to send notifications

  The job is scheduled with a delay to ensure ClickHouse has merged the new data.
  """
  use Oban.Worker, max_attempts: 3

  alias Tuist.Alerts.Workers.FlakyTestAlertWorker
  alias Tuist.Projects
  alias Tuist.Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "test_case_ids" => test_case_ids}}) do
    case Projects.get_project_by_id(project_id) do
      nil ->
        :ok

      project ->
        check_and_mark_flaky_test_cases(project, test_case_ids)
        :ok
    end
  end

  defp check_and_mark_flaky_test_cases(_project, []), do: :ok

  defp check_and_mark_flaky_test_cases(project, test_case_ids) do
    threshold = project.auto_mark_flaky_threshold
    auto_quarantine = project.auto_quarantine_flaky_tests

    flaky_counts = Runs.get_flaky_runs_groups_counts_for_test_cases(test_case_ids)

    Enum.each(test_case_ids, fn test_case_id ->
      flaky_count = Map.get(flaky_counts, test_case_id, 0)
      check_and_mark_flaky(project.id, test_case_id, flaky_count, threshold, auto_quarantine)
    end)
  end

  defp check_and_mark_flaky(_project_id, _test_case_id, flaky_count, threshold, _auto_quarantine)
       when flaky_count < threshold, do: :ok

  defp check_and_mark_flaky(project_id, test_case_id, flaky_count, _threshold, auto_quarantine) do
    with {:ok, test_case} <- Runs.get_test_case_by_id(test_case_id),
         false <- test_case.is_flaky do
      update_attrs =
        if auto_quarantine do
          %{is_flaky: true, is_quarantined: true}
        else
          %{is_flaky: true}
        end

      case Runs.update_test_case(test_case_id, update_attrs) do
        {:ok, _updated_test_case} ->
          enqueue_alert(project_id, test_case_id, flaky_count, auto_quarantine)

        {:error, _reason} ->
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp enqueue_alert(project_id, test_case_id, flaky_count, auto_quarantine) do
    %{
      test_case_id: test_case_id,
      project_id: project_id,
      auto_quarantined: auto_quarantine,
      flaky_runs_count: flaky_count
    }
    |> FlakyTestAlertWorker.new()
    |> Oban.insert!()
  end
end
