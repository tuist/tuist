defmodule Tuist.Alerts.Workers.FlakyTestAlertWorker do
  @moduledoc """
  A job that sends Slack notifications when a test case becomes flaky.

  This worker is enqueued when a test case transitions from non-flaky to flaky.
  It checks all flaky test alert rules for the project and sends notifications
  if the test case's flaky runs count exceeds the rule's threshold.

  The job is unique per test_case_id only while being processed - once completed,
  a new job can be inserted for the same test case.
  """
  use Oban.Worker,
    max_attempts: 3,
    unique: [keys: [:test_case_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Alerts
  alias Tuist.Repo
  alias Tuist.Runs
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"test_case_id" => test_case_id, "project_id" => project_id}}) do
    with {:ok, test_case} <- Runs.get_test_case_by_id(test_case_id) do
      flaky_runs_count = Runs.get_flaky_runs_groups_count_for_test_case(test_case_id)
      rules = Alerts.get_project_flaky_test_alert_rules(project_id)

      for rule <- rules do
        check_and_notify(rule, test_case, flaky_runs_count)
      end

      :ok
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
        Slack.send_flaky_test_alert(alert)
    end
  end
end
