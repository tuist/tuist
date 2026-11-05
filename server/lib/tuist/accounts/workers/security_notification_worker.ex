defmodule Tuist.Accounts.Workers.SecurityNotificationWorker do
  @moduledoc """
  Security notifications are queued in the same transaction as the account
  change or recovery-code consumption, so delivery failures can be retried.
  Job arguments never contain credentials or recovery codes.
  """
  use Oban.Worker, queue: :default, max_attempts: 10

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier

  def enqueue(user, event) do
    %{"user_id" => user.id, "event" => to_string(event)}
    |> new()
    |> Oban.insert!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => id, "event" => event}}) do
    if user = Accounts.get_user_by_id(id) do
      result =
        case event do
          "mfa_enabled" -> UserNotifier.deliver_mfa_change_notification(user, true)
          "mfa_disabled" -> UserNotifier.deliver_mfa_change_notification(user, false)
          "passkey_added" -> UserNotifier.deliver_passkey_change_notification(user, true)
          "passkey_removed" -> UserNotifier.deliver_passkey_change_notification(user, false)
          "recovery_used" -> UserNotifier.deliver_recovery_notification(user, :used)
          "recovery_regenerated" -> UserNotifier.deliver_recovery_notification(user, :regenerated)
        end

      case result do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end
end
