defmodule Tuist.Billing.Workers.PaymentGraceStartedNotificationWorker do
  @moduledoc """
  Delivers one admin's email saying a subscription is overdue and until when
  it keeps its plan, so a failed delivery retries without resending it to the
  admins who already got theirs.

  A job without a `user_id` fans out instead: it reads the subscription when
  it runs and queues one delivery per current admin with the subscription's
  current deadline. That is the shape a migration can insert by SQL, knowing
  only the subscription:

      %{"subscription_id" => subscriptions.id, "notice" => "policy"}

  `"notice" => "policy"` is the one-off notice for subscriptions that were
  already past due when the grace period was introduced. Without it, the
  email is the one an invoiced subscription gets when it turns past due.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:subscription_id, :grace_ends_at, :user_id], period: :infinity]

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Accounts.UserNotifier
  alias Tuist.Billing.PaymentFailedNotifications
  alias Tuist.Billing.Subscription
  alias Tuist.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "account_id" => account_id,
            "user_id" => user_id,
            "subscription_id" => subscription_id,
            "grace_ends_at" => grace_ends_at
          } = args
      }) do
    # A payment, or a deadline that passed before this ran, leaves nothing
    # true to say: the account is either paid up or told by the expiry email.
    with {:ok, account} <- Accounts.get_account_by_id(account_id),
         %User{} = user <- Accounts.get_user_by_id(user_id),
         true <- Accounts.owns_account_or_is_admin_to_account_organization?(user, account),
         %Subscription{} = subscription <-
           PaymentFailedNotifications.grace_episode_subscription(subscription_id, account_id, grace_ends_at),
         true <- Subscription.entitled?(subscription) do
      case deliver(notice(args), user, account, Subscription.payment_grace_ends_at(subscription)) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> :ok
    end
  end

  def perform(%Oban.Job{args: %{"subscription_id" => subscription_id} = args}) do
    with %Subscription{status: "past_due", plan: plan} = subscription when plan != :air <-
           Repo.get(Subscription, subscription_id),
         {:ok, account} <- Accounts.get_account_by_id(subscription.account_id) do
      PaymentFailedNotifications.enqueue_payment_grace_started(account, subscription, notice: notice(args))
    end

    :ok
  end

  defp notice(%{"notice" => "policy"}), do: :policy
  defp notice(_args), do: :started

  defp deliver(:policy, user, account, deadline),
    do: UserNotifier.deliver_payment_grace_policy_notification(user, account, deadline)

  defp deliver(:started, user, account, deadline),
    do: UserNotifier.deliver_payment_grace_started_notification(user, account, deadline)
end
