defmodule Tuist.Alerts.Workers.FlakyTestAlertWorker do
  @moduledoc """
  A job that sends Slack notifications when a test case becomes flaky.

  This worker is enqueued when a test case transitions from non-flaky to flaky.
  It supports two modes:
  1. Simplified alerts - uses project-level flaky_test_alerts_enabled flag
  2. Rule-based alerts - checks all flaky test alert rules for the project

  The job is unique per test_case_id only while being processed - once completed,
  a new job can be inserted for the same test case.
  """
  use Oban.Worker,
    max_attempts: 3,
    unique: [keys: [:test_case_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Alerts
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Runs
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"test_case_id" => test_case_id, "project_id" => project_id} = args
    was_auto_quarantined = Map.get(args, "was_auto_quarantined", false)

    with {:ok, test_case} <- Runs.get_test_case_by_id(test_case_id),
         %Projects.Project{} = project <- Projects.get_project_by_id(project_id) do
      flaky_runs_count = Runs.get_flaky_runs_groups_count_for_test_case(test_case_id)

      # If simplified alerts are enabled, use them exclusively (they replace rule-based alerts)
      if project.flaky_test_alerts_enabled do
        send_simplified_alert(project, test_case, flaky_runs_count, was_auto_quarantined)
      else
        # Fall back to rule-based alerts only if simplified alerts are not enabled
        rules = Alerts.get_project_flaky_test_alert_rules(project)

        for rule <- rules do
          check_and_notify(rule, test_case, flaky_runs_count)
        end
      end

      :ok
    end
  end

  defp send_simplified_alert(project, test_case, flaky_runs_count, was_auto_quarantined) do
    project = Repo.preload(project, account: :slack_installation)

    cond do
      not project.flaky_test_alerts_enabled ->
        :ok

      is_nil(project.flaky_test_alerts_slack_channel_id) ->
        :ok

      is_nil(project.account.slack_installation) ->
        :ok

      true ->
        Slack.send_simplified_flaky_test_alert(project, test_case, flaky_runs_count, was_auto_quarantined)
    end
  end

  defp check_and_notify(rule, test_case, flaky_runs_count) do
    rule = Repo.preload(rule, project: [account: :slack_installation])

    cond do
      flaky_runs_count < rule.trigger_threshold ->
        :ok

      is_nil(rule.slack_channel_id) ->
        :ok

      is_nil(rule.project.account.slack_installation) ->
        :ok

      true ->
        {:ok, alert} =
          Alerts.create_flaky_test_alert(%{
            flaky_test_alert_rule_id: rule.id,
            flaky_runs_count: flaky_runs_count,
            test_case_id: test_case.id,
            test_case_name: test_case.name,
            test_case_module_name: test_case.module_name,
            test_case_suite_name: test_case.suite_name
          })

        alert = Repo.preload(alert, flaky_test_alert_rule: [project: [account: :slack_installation]])
        :ok = Slack.send_flaky_test_alert(alert)
    end
  end
end
