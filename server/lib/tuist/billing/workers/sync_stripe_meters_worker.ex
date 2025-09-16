defmodule Tuist.Billing.Workers.SyncStripeMetersWorker do
  @moduledoc """
  A daily job that queues per-customer jobs to update billing meters in Stripe with yesterday's usage metrics.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker

  @impl Oban.Worker
  def perform(_args) do
    customer_ids = Accounts.list_billable_customers()

    customer_ids
    |> Enum.map(&SyncCustomerStripeMetersWorker.new(%{customer_id: &1}))
    |> Oban.insert_all()
  end
end
