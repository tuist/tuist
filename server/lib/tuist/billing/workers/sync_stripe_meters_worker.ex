defmodule Tuist.Billing.Workers.SyncStripeMetersWorker do
  @moduledoc """
  Queues per-customer jobs to update Stripe meters for a stable reporting date.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    usage_date = reporting_date(args)
    customer_ids = Accounts.list_billable_customers()

    customer_ids
    |> Enum.map(
      &SyncCustomerStripeMetersWorker.new(%{
        customer_id: &1,
        usage_date: Date.to_iso8601(usage_date)
      })
    )
    |> Oban.insert_all()
  end

  defp reporting_date(%{"usage_date" => usage_date}), do: Date.from_iso8601!(usage_date)

  defp reporting_date(_args) do
    Tuist.Time.utc_now() |> DateTime.to_date() |> Date.add(-1)
  end
end
