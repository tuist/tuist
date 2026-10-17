defmodule Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorker do
  @moduledoc """
  Delivers one admin's email saying the account moved to Air because Stripe
  stopped retrying its subscription payment, so a failed delivery retries
  without resending it to the admins who already got theirs.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing
  alias Tuist.Billing.Subscription
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "user_id" => user_id}}) do
    # An invoice paid before this ran leaves the account on its plan again.
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %User{} = user <- Accounts.get_user_by_id(user_id),
         true <- Accounts.owns_account_or_is_admin_to_account_organization?(user, account),
         true <- Billing.payment_failed?(account),
         false <- told_about_air_already?(account) do
      case UserNotifier.deliver_subscription_unpaid_notification(user, account) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end

  # A subscription that stayed past due beyond its grace period was already
  # announced as limited to Air by `PaymentGraceExpiredNotificationWorker`.
  # Stripe marking it unpaid afterwards changes nothing for the account. The
  # webhook already skips queuing then; like every other condition here, it
  # is checked again at delivery.
  defp told_about_air_already?(account) do
    Repo.exists?(
      from(s in Subscription,
        where: s.account_id == ^account.id and s.status == "unpaid",
        where:
          s.payment_grace_expiry_notified_at >=
            datetime_add(s.past_due_since, ^Subscription.payment_grace_period_days(), "day")
      )
    )
  end
end
