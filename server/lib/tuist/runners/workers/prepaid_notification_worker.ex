defmodule Tuist.Runners.Workers.PrepaidNotificationWorker do
  @moduledoc """
  Retries each recipient independently. A row lock serializes delivery across
  replicas, including duplicate jobs. Like all external email sends this is
  at-least-once: a crash after SMTP accepts but before commit may resend.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Repo
  alias Tuist.Runners.PrepaidNotification
  alias Tuist.Runners.PrepaidNotifications

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    case Repo.transaction(fn ->
           notification =
             PrepaidNotification
             |> where([n], n.id == ^id)
             |> lock("FOR UPDATE")
             |> Repo.one()
             |> Repo.preload([:activation, :account, :user])

           maybe_deliver(notification)
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_deliver(nil), do: :ok
  defp maybe_deliver(%{delivered_at: delivered_at}) when not is_nil(delivered_at), do: :ok

  defp maybe_deliver(notification) do
    %{activation: activation, account: account, user: user} = notification
    now = DateTime.truncate(DateTime.utc_now(), :second)

    if PrepaidNotifications.active?(activation, account, now) &&
         Accounts.owns_account_or_is_admin_to_account_organization?(user, account) do
      usage = PrepaidNotifications.usage_cents(activation, account, now)
      budget = PrepaidNotifications.budget_cents(activation)

      if PrepaidNotifications.threshold(usage, budget) == notification.threshold do
        updated = %{notification | usage_cents: usage, budget_cents: budget}

        case UserNotifier.deliver_runner_prepaid_notification(user, account, updated) do
          {:ok, _} ->
            notification
            |> Ecto.Changeset.change(delivered_at: now, usage_cents: usage, budget_cents: budget)
            |> Repo.update!()

            :ok

          {:error, reason} ->
            {:error, reason}
        end
      else
        :ok
      end
    else
      :ok
    end
  end
end
