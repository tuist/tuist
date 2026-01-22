defmodule Tuist.Alerts.Workers.FlakyTestAlertWorker do
  @moduledoc """
  A job that sends Slack notifications when a test case becomes flaky.

  This worker is enqueued when a test case transitions from non-flaky to flaky.
  It uses project-level flaky_test_alerts_enabled flag and sends alerts to the
  configured Slack channel.

  The job is unique per test_case_id only while being processed - once completed,
  a new job can be inserted for the same test case.
  """
  use Oban.Worker,
    max_attempts: 3,
    unique: [keys: [:test_case_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Runs
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"test_case_id" => test_case_id, "project_id" => project_id, "flaky_runs_count" => flaky_runs_count} = args
    auto_quarantined = Map.get(args, "auto_quarantined", false)

    with {:ok, test_case} <- Runs.get_test_case_by_id(test_case_id),
         %Projects.Project{} = project <- Projects.get_project_by_id(project_id) do
      send_alert(project, test_case, flaky_runs_count, auto_quarantined)
      :ok
    end
  end

  defp send_alert(project, test_case, flaky_runs_count, auto_quarantined) do
    project = Repo.preload(project, account: :slack_installation)

    cond do
      not project.flaky_test_alerts_enabled ->
        :ok

      is_nil(project.flaky_test_alerts_slack_channel_id) ->
        :ok

      is_nil(project.account.slack_installation) ->
        :ok

      true ->
        Slack.send_flaky_test_alert(project, test_case, flaky_runs_count, auto_quarantined)
    end
  end
end
