defmodule Tuist.Billing.Workers.SyncStripeMetersWorker do
  @moduledoc """
  Chooses one half-open billing period and queues one customer snapshot
  job per billable customer with those immutable boundaries.

  The daily cron passes no arguments and gets the previous UTC day. A
  caller can instead pass explicit `period_start` / `period_end` unix
  microsecond boundaries to report an arbitrary window: reporting the
  current day before the cron would reach it, re-reporting a day whose
  jobs were lost, or backfilling after an outage. Stripe deduplicates on
  an identifier derived from the customer, meter, and exact window, so
  replaying a window that already reported is a no-op rather than a
  double count.
  """
  use Oban.Worker, max_attempts: 1

  alias Tuist.Accounts
  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"period_start" => period_start, "period_end" => period_end}}) do
    sync(
      DateTime.from_unix!(period_start, :microsecond),
      DateTime.from_unix!(period_end, :microsecond)
    )
  end

  def perform(_args) do
    period_end = Timex.beginning_of_day(DateTime.utc_now())
    sync(Timex.shift(period_end, days: -1), period_end)
  end

  defp sync(%DateTime{} = period_start, %DateTime{} = period_end) do
    Accounts.list_billable_customers()
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
