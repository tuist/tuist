defmodule Tuist.Alerts.Workers.AlertWorker do
  @moduledoc """
  A periodic job that checks alert rule conditions and sends Slack notifications.

  Runs every 10 minutes. The cron job finds all alert rules and enqueues
  individual alert check jobs. This allows tracking cooldowns per alert rule.
  """
  use Oban.Worker, max_attempts: 3

  alias Tuist.Alerts
  alias Tuist.Repo
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule_id}}) do
    {:ok, alert_rule} = Alerts.get_alert_rule(alert_rule_id)
    :ok = check_and_notify(alert_rule)
  end

  def perform(_job) do
    alert_rules = Alerts.get_all_alert_rules()

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
      not Alerts.cooldown_elapsed?(alert_rule) ->
        :ok

      is_nil(alert_rule.project.account.slack_installation) ->
        :ok

      true ->
        case Alerts.evaluate(alert_rule) do
          {:triggered, result} ->
            {:ok, alert} =
              Alerts.create_alert(%{
                alert_rule_id: alert_rule.id,
                current_value: result.current,
                previous_value: result.previous
              })

            alert = Repo.preload(alert, alert_rule: [project: [account: :slack_installation]])
            :ok = Slack.send_alert(alert)

          :ok ->
            :ok
        end
    end
  end
end
