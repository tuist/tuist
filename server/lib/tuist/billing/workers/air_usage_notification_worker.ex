defmodule Tuist.Billing.Workers.AirUsageNotificationWorker do
  @moduledoc """
  Delivers each admin's Air usage notification independently so failures retry
  without resending emails already delivered to other admins.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    case Repo.transaction(fn -> deliver(id) end) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp deliver(id) do
    notification =
      Repo.one(from(n in AirUsageNotification, where: n.id == ^id, lock: "FOR UPDATE", preload: [:account, :user]))

    if notification && is_nil(notification.delivered_at) && relevant?(notification) do
      case UserNotifier.deliver_air_usage_notification(notification.user, notification.account, notification) do
        {:ok, _email} ->
          notification
          |> Ecto.Changeset.change(delivered_at: DateTime.truncate(DateTime.utc_now(), :second))
          |> Repo.update!()

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end
  end

  defp relevant?(notification) do
    account = notification.account
    limit = Billing.get_payment_thresholds().remote_cache_hits
    period_start = AirUsageNotifications.period_start(account, DateTime.utc_now())

    Billing.effective_plan(account) == :air &&
      Accounts.owns_account_or_is_admin_to_account_organization?(notification.user, account) &&
      DateTime.compare(notification.period_start, period_start) == :eq &&
      AirUsageNotifications.threshold(account.current_month_remote_cache_hits_count, limit) == notification.threshold
  end
end
