defmodule Tuist.Alerts.Workers.AlertWorker do
  @moduledoc """
  A periodic job that checks alert rule conditions and sends Slack notifications.

  Runs every 10 minutes. The cron job finds all alert rules and enqueues
  individual alert check jobs. This allows tracking cooldowns per alert rule.
  """
  use Oban.Worker, max_attempts: 3

  alias Tuist.Alerts
  alias Tuist.Alerts.Alert
  alias Tuist.Repo
  alias Tuist.Slack

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"alert_rule_id" => alert_rule_id}} = job) do
    {:ok, alert_rule} = Alerts.get_alert_rule(alert_rule_id)
    check_and_notify(alert_rule, last_attempt?(job))
  end

  def perform(_job) do
    alert_rules = Alerts.get_all_alert_rules()

    for alert_rule <- alert_rules do
      %{alert_rule_id: alert_rule.id}
      |> __MODULE__.new(unique: [period: 300, keys: [:alert_rule_id]])
      |> Oban.insert!()
    end

    :ok
  end

  defp check_and_notify(alert_rule, last_attempt?) do
    alert_rule = Repo.preload(alert_rule, project: [account: :slack_installation])

    cond do
      not Alerts.cooldown_elapsed?(alert_rule) ->
        :ok

      not slack_configured?(alert_rule) ->
        :ok

      true ->
        case Alerts.evaluate(alert_rule) do
          {:triggered, result} ->
            notify(alert_rule, result, last_attempt?)

          :ok ->
            :ok
        end
    end
  end

  # The alert row starts the rule's cooldown, so it is only written once Slack
  # took the alert: a transient failure leaves the retry free to deliver it.
  # A permanent one (a revoked webhook, a request Slack rejects), or any
  # failure on the job's last attempt, starts the cooldown too, so a dead
  # destination fails once a day rather than on every 10-minute tick. The
  # request runs outside any transaction so it holds no connection.
  defp notify(alert_rule, result, last_attempt?) do
    attrs = %{alert_rule_id: alert_rule.id, current_value: result.current, previous_value: result.previous}
    alert = struct(Alert, Map.merge(attrs, %{alert_rule: alert_rule, inserted_at: DateTime.utc_now(:second)}))

    case Slack.send_alert(alert) do
      :ok ->
        {:ok, _alert} = Alerts.create_alert(attrs)
        :ok

      {:error, reason} = error ->
        if last_attempt? or permanent_failure?(reason) do
          {:ok, _alert} = Alerts.create_alert(attrs)
          {:discard, reason}
        else
          error
        end
    end
  end

  defp permanent_failure?(:webhook_revoked), do: true
  defp permanent_failure?({:bad_request, _status, _body, _request}), do: true
  defp permanent_failure?(_reason), do: false

  # Jobs built by hand (tests, manual runs) carry no attempt counters.
  defp last_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts})
       when is_integer(attempt) and is_integer(max_attempts), do: attempt >= max_attempts

  defp last_attempt?(_job), do: false

  # Either a per-channel webhook URL (preferred) or a legacy account-level
  # bot token (with a channel id) is enough to deliver an alert.
  defp slack_configured?(%{slack_webhook_url: url}) when is_binary(url) and url != "", do: true

  defp slack_configured?(%{
         slack_channel_id: channel_id,
         project: %{account: %{slack_installation: %{access_token: token}}}
       })
       when is_binary(channel_id) and is_binary(token), do: true

  defp slack_configured?(_), do: false
end
