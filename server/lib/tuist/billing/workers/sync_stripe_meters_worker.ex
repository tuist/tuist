defmodule Tuist.Billing.Workers.SyncStripeMetersWorker do
  @moduledoc """
  Chooses the previous day's half-open billing period once and queues
  one customer snapshot job with those immutable boundaries.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker

  @impl Oban.Worker
  def perform(_args) do
    now = DateTime.utc_now()
    period_end = Timex.beginning_of_day(now)
    period_start = Timex.shift(period_end, days: -1)

    customer_ids = Accounts.list_billable_customers()

    customer_ids
    |> Enum.map(
      &SyncCustomerStripeMetersWorker.new(%{
        customer_id: &1,
        period_start: DateTime.to_unix(period_start, :microsecond),
        period_end: DateTime.to_unix(period_end, :microsecond)
      })
    )
    |> Oban.insert_all()

    :ok
  end
end
