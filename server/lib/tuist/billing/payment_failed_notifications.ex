defmodule Tuist.Billing.PaymentFailedNotifications do
  @moduledoc """
  Queues the email telling an account's admins that a subscription payment
  failed, and until when the account keeps its plan.
  """

  alias Tuist.Accounts
  alias Tuist.Billing.AirUsageNotifications
  alias Tuist.Billing.Workers.PaymentFailedNotificationWorker

  # How long Stripe's Smart Retries keep retrying a failed subscription
  # payment before marking the subscription `unpaid`, which is when the
  # account loses its plan. Stripe does not expose the setting through its
  # API, so this has to match Revenue recovery → Retries in the dashboard.
  @retry_window_days 14

  @doc """
  Queues one email per admin for the first failed charge of an automatically
  charged subscription invoice.

  Stripe reports every retry as its own failure. Only the first one starts
  the retry window, so later attempts, and a redelivery of the same one,
  queue nothing new.
  """
  def enqueue(%{attempt_count: 1, collection_method: "charge_automatically"} = invoice, %DateTime{} = failed_at) do
    with true <- subscription_invoice?(invoice),
         {:ok, account} <- Accounts.get_account_from_customer_id(invoice.customer) do
      plan_active_until = failed_at |> DateTime.add(@retry_window_days, :day) |> DateTime.to_iso8601()

      account
      |> AirUsageNotifications.recipients()
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(
        &PaymentFailedNotificationWorker.new(%{
          invoice_id: invoice.id,
          account_id: account.id,
          user_id: &1.id,
          plan_active_until: plan_active_until
        })
      )
      |> Enum.each(&Oban.insert!/1)
    end

    :ok
  end

  def enqueue(_invoice, _failed_at), do: :ok

  defp subscription_invoice?(%{billing_reason: "subscription" <> _}), do: true
  defp subscription_invoice?(_invoice), do: false
end
