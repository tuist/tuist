defmodule Tuist.Slack.Workers.AlertWorker do
  @moduledoc """
  A periodic job that checks alert conditions and sends Slack notifications.

  Runs every 10 minutes. The cron job finds all enabled alerts and enqueues
  individual alert check jobs. This allows tracking cooldowns per alert.
  """
  use Oban.Worker, max_attempts: 3

  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Alerts
  alias Tuist.Slack.Client, as: SlackClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => alert_id}}) do
    case Slack.get_alert(alert_id) do
      {:error, :not_found} ->
        :ok

      {:ok, alert} ->
        check_and_notify(alert)
    end
  end

  def perform(_job) do
    alerts = Slack.list_enabled_alerts()

    for alert <- alerts do
      %{alert_id: alert.id}
      |> __MODULE__.new(unique: [period: 300, keys: [:alert_id]])
      |> Oban.insert()
    end

    :ok
  end

  defp check_and_notify(alert) do
    alert = Repo.preload(alert, project: [account: :slack_installation])

    cond do
      not alert.enabled ->
        :ok

      not Slack.cooldown_elapsed?(alert) ->
        :ok

      is_nil(alert.project.account.slack_installation) ->
        :ok

      true ->
        case Alerts.evaluate(alert) do
          {:triggered, result} ->
            send_alert(alert, result)
            Slack.update_alert_triggered_at(alert)
            :ok

          :ok ->
            :ok
        end
    end
  end

  defp send_alert(alert, result) do
    slack_installation = alert.project.account.slack_installation
    blocks = Alerts.build_alert_blocks(alert, result)
    SlackClient.post_message(slack_installation.access_token, alert.slack_channel_id, blocks)
  end
end
