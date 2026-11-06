defmodule Tuist.Automations.Workers.SlackNotificationWorker do
  @moduledoc false
  use Oban.Worker, queue: :automation_notifications, max_attempts: 10

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Alert
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Slack
  alias Tuist.Slack.Client
  alias Tuist.Slack.Installation

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => id, "action" => action, "blocks" => blocks}}) do
    case Automations.get_alert(id) do
      {:ok, %Alert{enabled: true} = alert} ->
        # Cancel queued messages whose destination or template has been removed.
        if action in alert.trigger_actions or (alert.recovery_enabled and action in alert.recovery_actions) do
          deliver(alert, action, blocks)
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp deliver(_alert, %{"webhook_url_encrypted" => encrypted}, blocks) when is_binary(encrypted) and encrypted != "" do
    case Slack.decrypt_webhook_url(encrypted) do
      {:ok, url} -> Client.deliver_once({:webhook, url}, blocks)
      _ -> {:discard, :invalid_webhook}
    end
  end

  defp deliver(alert, %{"channel" => channel}, blocks) do
    project = alert.project_id |> Projects.get_project_by_id() |> Repo.preload(account: :slack_installation)

    case project.account.slack_installation do
      %Installation{access_token: token} -> Client.deliver_once({:channel, token, channel}, blocks)
      _ -> {:discard, :missing_credentials}
    end
  end
end
