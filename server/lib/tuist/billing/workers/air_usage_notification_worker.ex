defmodule Tuist.Billing.Workers.AirUsageNotificationWorker do
  @moduledoc """
  Delivers each admin's Air usage notification independently so failures retry
  without resending emails already delivered to other admins.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Accounts
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing
  alias Tuist.Billing.AirUsageNotification
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    notification = AirUsageNotification |> Repo.get(id) |> Repo.preload([:account, :user])

    if notification && is_nil(notification.delivered_at) && relevant?(notification) do
      {usage, limit} = AirUsageNotifications.usage(notification.account, notification.metric)

      if AirUsageNotifications.threshold(usage, limit) == notification.threshold do
        deliver(notification, usage, limit)
      else
        :ok
      end
    else
      :ok
    end
  end

  defp deliver(notification, usage, limit) do
    case UserNotifier.deliver_air_usage_notification(notification.user, notification.account, %{
           notification
           | usage: usage,
             limit: limit
         }) do
      {:ok, _email} ->
        notification
        |> Ecto.Changeset.change(
          usage: usage,
          limit: limit,
          delivered_at: DateTime.truncate(DateTime.utc_now(), :second)
        )
        |> Repo.update!()

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp relevant?(notification) do
    account = notification.account
    period_start = AirUsageNotifications.period_start(account, DateTime.utc_now(), notification.metric)

    Billing.effective_plan(account) == :air &&
      Accounts.owns_account_or_is_admin_to_account_organization?(notification.user, account) &&
      DateTime.compare(notification.period_start, period_start) == :eq &&
      AirUsageNotifications.eligible?(account, notification.metric)
  end
end
