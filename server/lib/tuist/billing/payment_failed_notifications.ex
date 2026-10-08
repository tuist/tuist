defmodule Tuist.Billing.PaymentFailedNotifications do
  @moduledoc """
  Queues the emails telling an account's admins that a subscription payment
  failed, and that the account lost its plan once Stripe stopped retrying.
  """

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker
  alias Tuist.Billing.Workers.SubscriptionUnpaidNotificationWorker

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

  defp subscription_invoice?(%{billing_reason: "subscription" <> _}), do: true
  defp subscription_invoice?(_invoice), do: false
end
