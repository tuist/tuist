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

  # Slack errors from a token refresh that mean the installation itself is gone.
  @revoked_installation_errors ~w(invalid_refresh_token invalid_auth token_revoked account_inactive)

  @impl Oban.Worker
  def timeout(_job), do: to_timeout(minute: 1)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_id" => id, "action" => action, "blocks" => blocks}}) do
    case Automations.get_alert(id) do
      {:ok, %Alert{enabled: true} = alert} ->
        # Cancel queued messages whose destination or template has been removed.
        # Actions match by webhook URL rather than ciphertext, which changes when
        # `Tuist.Vault.Reencryption` moves it to a new key, so re-encrypting an
        # alert does not cancel what it queued. That needs the queued copy to be
        # readable, which is why a rotation drains these jobs before dropping the
        # old key; the alert's own copy is the one delivered.
        actions =
          if alert.recovery_enabled, do: alert.trigger_actions ++ alert.recovery_actions, else: alert.trigger_actions

        case Enum.find(actions, &same_action?(&1, action)) do
          nil -> :ok
          current -> deliver(alert, current, blocks)
        end

      _ ->
        :ok
    end
  end

  defp same_action?(action, action), do: true

  defp same_action?(a, b) do
    Automations.redact_action(a) == Automations.redact_action(b) and
      match?({:ok, _}, webhook_url(a)) and webhook_url(a) == webhook_url(b)
  end

  defp webhook_url(action), do: action |> Map.get("webhook_url_encrypted") |> Slack.decrypt_webhook_url()

  defp deliver(_alert, %{"webhook_url_encrypted" => encrypted}, blocks) when is_binary(encrypted) and encrypted != "" do
    case Slack.decrypt_webhook_url(encrypted) do
      {:ok, url} -> Client.deliver_once({:webhook, url}, blocks)
      _ -> {:discard, :invalid_webhook}
    end
  end

  defp deliver(alert, %{"channel" => channel}, blocks) do
    project = alert.project_id |> Projects.get_project_by_id() |> Repo.preload(account: :slack_installation)

    case project.account.slack_installation do
      %Installation{} = installation ->
        case Slack.installation_access_token(installation) do
          {:ok, token} -> Client.deliver_once({:channel, token, channel}, blocks)
          {:error, error} when error in @revoked_installation_errors -> {:discard, :slack_rejected}
          {:error, _reason} -> {:error, :slack_token_refresh_failed}
        end

      _ ->
        {:discard, :missing_credentials}
    end
  end
end
