defmodule Tuist.Alerts.Workers.FlakyThresholdCheckWorker do
  @moduledoc """
  A job that checks if a test case should be marked as flaky based on the threshold setting.

  This worker runs after test case runs are created to:
  1. Count the total flaky runs for the test case
  2. If count >= project's auto_mark_flaky_threshold and auto_mark_flaky_tests is enabled:
     - Mark the test case as flaky
     - Auto-quarantine if enabled
     - Trigger flaky test alerts
  """
  use Oban.Worker,
    max_attempts: 3,
    unique: [keys: [:test_case_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Alerts.Workers.FlakyTestAlertWorker
  alias Tuist.Projects
  alias Tuist.Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_case_id" => test_case_id, "project_id" => project_id}}) do
    with {:ok, test_case} <- Runs.get_test_case_by_id(test_case_id),
         %Projects.Project{} = project <- Projects.get_project_by_id(project_id) do
      # Skip if test case is already marked as flaky
      if test_case.is_flaky do
        :ok
      else
        check_and_mark_flaky(project, test_case)
      end
    else
      _ -> :ok
    end
  end

  defp check_and_mark_flaky(%{auto_mark_flaky_tests: true} = project, test_case) do
    flaky_runs_count = Runs.get_flaky_runs_groups_count_for_test_case(test_case.id)

    if flaky_runs_count >= project.auto_mark_flaky_threshold do
      {:ok, _updated_test_case} = Runs.set_test_case_flaky(test_case.id, true)

      auto_quarantined =
        if project.auto_quarantine_flaky_tests do
          {:ok, _} = Runs.set_test_case_quarantined(test_case.id, true)
          true
        else
          false
        end

      %{test_case_id: test_case.id, project_id: project.id, auto_quarantined: auto_quarantined, flaky_runs_count: flaky_runs_count}
      |> FlakyTestAlertWorker.new()
      |> Oban.insert!()
    end

    :ok
  end

  defp check_and_mark_flaky(_project, _test_case), do: :ok
end
