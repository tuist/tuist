defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorker do
  @moduledoc """
  Snapshots a customer's meter values for the parent billing period
  and fans out one Stripe reporting job per meter.
  """
  use Oban.Worker

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"customer_id" => customer_id, "period_start" => period_start, "period_end" => period_end}
      }) do
    sync(
      customer_id,
      DateTime.from_unix!(period_start, :microsecond),
      DateTime.from_unix!(period_end, :microsecond)
    )
  end

  # Transitional clause for jobs enqueued by the pre-fan-out parent worker,
  # which carried only the customer id. During a rolling deploy those jobs
  # can still be draining from the queue; without this clause a new-code node
  # would raise FunctionClauseError on them, exhaust their retries, and
  # silently drop a day of usage for that customer. We recompute the period
  # the same way the parent now does (yesterday's half-open day). Safe to
  # remove once no pre-deploy jobs remain in the queue.
  def perform(%Oban.Job{args: %{"customer_id" => customer_id}}) do
    period_end = Timex.beginning_of_day(DateTime.utc_now())
    period_start = Timex.shift(period_end, days: -1)
    sync(customer_id, period_start, period_end)
  end

  defp sync(customer_id, %DateTime{} = period_start, %DateTime{} = period_end) do
    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{
        customer_id: customer_id,
        period_start: period_start,
        period_end: period_end
      })
    end

    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)

    account
    |> Billing.customer_meter_values(period_start, period_end,
      include_qa: FunWithFlags.enabled?(:qa_billing_enabled, for: account)
    )
    |> Enum.map(fn meter ->
      SyncCustomerStripeMeterWorker.new(%{
        customer_id: customer_id,
        event_name: meter.event_name,
        value: meter.value,
        period_start: DateTime.to_unix(period_start, :microsecond),
        period_end: DateTime.to_unix(period_end, :microsecond)
      })
    end)
    |> Oban.insert_all()

    :ok
  end
end
