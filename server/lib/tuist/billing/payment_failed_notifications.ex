defmodule Tuist.Billing.PaymentFailedNotifications do
  @moduledoc """
  Queues the email telling an account's admins that a subscription payment
  failed.
  """

  alias Tuist.Accounts
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker

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

  defp subscription_invoice?(%{billing_reason: "subscription" <> _}), do: true
  defp subscription_invoice?(_invoice), do: false
end
