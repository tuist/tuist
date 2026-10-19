defmodule Tuist.Billing.PaymentFailedNotifications do
  @moduledoc """
  Queues the emails telling an account's admins that a subscription payment
  failed, until when the plan is kept, and that the account lost its plan
  once the payment grace period ended or Stripe stopped retrying.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Subscription
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias Tuist.Billing.Workers.PaymentGraceExpiredNotificationWorker
  alias Tuist.Billing.Workers.PaymentGraceStartedNotificationWorker
  alias Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorker
  alias Tuist.Repo

  @doc """
  Queues one email per admin for the first failed charge of an automatically
  charged subscription invoice.

  Stripe reports every retry as its own failure. The email is about the
  failure rather than each attempt, so later attempts, and a redelivery of
  the same one, queue nothing new.
  """
  def enqueue(%{attempt_count: 1, collection_method: "charge_automatically"} = invoice) do
    with true <- subscription_invoice?(invoice),
         {:ok, account} <- Accounts.get_account_from_customer_id(invoice.customer) do
      account
      |> AirUsageNotifications.recipients()
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(
        &PaymentFailedNotificationWorker.new(%{
          invoice_id: invoice.id,
          account_id: account.id,
          user_id: &1.id
        })
      )
      |> Enum.each(&Oban.insert!/1)
    end

    :ok
  end

  def enqueue(_invoice), do: :ok

  @doc """
  Queues one email per admin telling them the account lost its plan: Stripe
  stopped retrying the payment and marked the subscription `unpaid`.
  """
  def enqueue_subscription_unpaid(%Account{} = account) do
    account
    |> AirUsageNotifications.recipients()
    |> Enum.uniq_by(& &1.id)
    |> Enum.each(&Oban.insert!(SubscriptionUnpaidNotificationWorker.new(%{account_id: account.id, user_id: &1.id})))
  end

  @doc """
  Queues one email per admin telling them that the persisted `subscription`
  is past due and until when it keeps its plan.

  Meant for subscriptions that are invoiced rather than charged, which never
  produce the failed charge `enqueue/1` reacts to. The caller decides that
  and calls this after persisting the transition. A subscription that is not
  past due, or whose grace period is already over, queues nothing: the
  expiry email covers the latter.

  `notice: :policy` sends the one-off notice for subscriptions that were
  already past due when the grace period was introduced, which also says
  the plan used to stay active for as long as the payment was retried.
  """
  def enqueue_payment_grace_started(%Account{} = account, %Subscription{} = subscription, opts \\ []) do
    if Subscription.entitled?(subscription) do
      extra_args =
        case Keyword.get(opts, :notice, :started) do
          :policy -> %{notice: "policy"}
          :started -> %{}
        end

      enqueue_grace_notification(account, subscription, PaymentGraceStartedNotificationWorker, extra_args)
    else
      :ok
    end
  end

  @doc """
  Queues one email per admin telling them the account is limited to Air
  because `subscription` stayed past due beyond its grace period.

  Inserted in the caller's transaction, so the sweep's durable marker and the
  jobs commit or roll back together.
  """
  def enqueue_payment_grace_expired(%Account{} = account, %Subscription{} = subscription) do
    enqueue_grace_notification(account, subscription, PaymentGraceExpiredNotificationWorker, %{})
  end

  @doc """
  The subscription a grace email was queued for, as long as it is still the
  same overdue episode: the row belongs to the account, has one of
  `statuses`, and its grace period still ends at `grace_ends_at`. A recovery
  clears the anchor and a new failure moves it, so either leaves this `nil`.

  Only `past_due` by default. The expiry email also accepts `unpaid`: Stripe
  can stop retrying between the sweep queuing it and its delivery, and the
  unpaid email is suppressed for an announced episode, so skipping here would
  leave the account told nothing. The anchor is kept through `unpaid`, so the
  deadline is still read from it.
  """
  def grace_episode_subscription(subscription_id, account_id, grace_ends_at, statuses \\ ["past_due"]) do
    with {:ok, expected, _offset} <- DateTime.from_iso8601(grace_ends_at),
         %Subscription{account_id: ^account_id, status: status} = subscription <-
           Repo.get(Subscription, subscription_id),
         true <- status in statuses,
         %DateTime{} = actual <- episode_grace_ends_at(subscription),
         :eq <- DateTime.compare(actual, expected) do
      subscription
    else
      _ -> nil
    end
  end

  defp episode_grace_ends_at(%Subscription{status: "unpaid", past_due_since: %DateTime{} = since}),
    do: DateTime.add(since, Subscription.payment_grace_period_days(), :day)

  defp episode_grace_ends_at(subscription), do: Subscription.payment_grace_ends_at(subscription)

  defp enqueue_grace_notification(account, subscription, worker, extra_args) do
    case Subscription.payment_grace_ends_at(subscription) do
      %DateTime{} = grace_ends_at ->
        account
        |> AirUsageNotifications.recipients()
        |> Enum.uniq_by(& &1.id)
        |> Enum.each(
          &Oban.insert!(
            worker.new(
              Map.merge(extra_args, %{
                account_id: account.id,
                user_id: &1.id,
                subscription_id: subscription.id,
                grace_ends_at: DateTime.to_iso8601(grace_ends_at)
              })
            )
          )
        )

      nil ->
        :ok
    end

    :ok
  end

  defp subscription_invoice?(%{billing_reason: "subscription" <> _}), do: true
  defp subscription_invoice?(_invoice), do: false
end
