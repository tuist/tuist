defmodule Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorker do
  @moduledoc """
  Delivers one admin's email saying the account moved to Air because Stripe
  stopped retrying its subscription payment, so a failed delivery retries
  without resending it to the admins who already got theirs.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "user_id" => user_id}}) do
    # An invoice paid before this ran leaves the account on its plan again.
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %User{} = user <- Accounts.get_user_by_id(user_id),
         true <- Accounts.owns_account_or_is_admin_to_account_organization?(user, account),
         true <- Billing.payment_failed?(account) do
      case UserNotifier.deliver_subscription_unpaid_notification(user, account) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end
end
