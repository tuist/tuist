defmodule Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorker do
  @moduledoc """
  Delivers one admin's email saying the account is limited to Air because its
  subscription stayed overdue past the payment grace period, so a failed
  delivery retries without resending it to the admins who already got theirs.

  Queued by `PaymentGraceExpirySweepWorker`, whose marker on the subscription
  is what keeps an episode from being announced twice once these jobs are
  pruned.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:subscription_id, :grace_ends_at, :user_id], period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing
  alias Tuist.Billing.PaymentFailedNotifications
  alias Tuist.Billing.Subscription

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "account_id" => account_id,
          "user_id" => user_id,
          "subscription_id" => subscription_id,
          "grace_ends_at" => grace_ends_at
        }
      }) do
    # An invoice paid before this ran leaves the account on its plan again.
    # Stripe giving up in between does not: the account is still on Air, and
    # the unpaid email defers to this one for the episode.
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %User{} = user <- Accounts.get_user_by_id(user_id),
         true <- Accounts.owns_account_or_is_admin_to_account_organization?(user, account),
         %Subscription{} = subscription <-
           PaymentFailedNotifications.grace_episode_subscription(subscription_id, account_id, grace_ends_at, [
             "past_due",
             "unpaid"
           ]),
         false <- Subscription.entitled?(subscription),
         true <- Billing.payment_failed?(account) do
      case UserNotifier.deliver_payment_grace_expired_notification(user, account) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end
end
