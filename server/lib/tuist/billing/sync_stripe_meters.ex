defmodule Tuist.Billing.SyncStripeMeters do
  @moduledoc """
  A job that gets pairs of customer id and usage metrics (remote cache hits and LLM tokens), and schedules jobs to push the measurements to Stripe.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.SyncCustomerStripeMeters

  @impl Oban.Worker
  def perform(_args) do
    customer_ids = Accounts.list_billable_customers()

    customer_ids
    |> Enum.map(&SyncCustomerStripeMeters.new(%{customer_id: &1}))
    |> Oban.insert_all()
  end
end
