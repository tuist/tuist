defmodule Tuist.Slack.Workers.AlertWorker do
  @moduledoc """
  A periodic job that checks alert rule conditions and sends Slack notifications.

  Runs every 10 minutes. The cron job finds all enabled alert rules and enqueues
  individual alert check jobs. This allows tracking cooldowns per alert rule.
  """
  use Oban.Worker, max_attempts: 3

  alias Tuist.Alerts
  alias Tuist.Repo
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule_id}}) do
    case Alerts.get_alert_rule(alert_rule_id) do
      {:error, :not_found} ->
        :ok

      {:ok, alert_rule} ->
        check_and_notify(alert_rule)
    end
  end

  def perform(_job) do
    alert_rules = Alerts.list_enabled_alert_rules()

    for alert_rule <- alert_rules do
      %{alert_rule_id: alert_rule.id}
      |> __MODULE__.new(unique: [period: 300, keys: [:alert_rule_id]])
      |> Oban.insert()
    end

    :ok
  end

  defp check_and_notify(alert_rule) do
    alert_rule = Repo.preload(alert_rule, project: [account: :slack_installation])

    cond do
      not alert_rule.enabled ->
        :ok

      not Alerts.cooldown_elapsed?(alert_rule) ->
        :ok

      is_nil(alert_rule.project.account.slack_installation) ->
        :ok

      true ->
        case Alerts.evaluate(alert_rule) do
          {:triggered, alert} ->
            slack_installation = alert_rule.project.account.slack_installation
            Slack.send_alert(alert, slack_installation)
            Alerts.update_alert_rule_triggered_at(alert_rule)
            :ok

          :ok ->
            :ok
        end
    end
  end
end
