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
    period_start_datetime = DateTime.from_unix!(period_start, :microsecond)
    period_end_datetime = DateTime.from_unix!(period_end, :microsecond)

    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{
        customer_id: customer_id,
        period_start: period_start_datetime,
        period_end: period_end_datetime
      })
    end

    {:ok, account} = Accounts.get_account_from_customer_id(customer_id)

    account
    |> Billing.customer_meter_values(period_start_datetime, period_end_datetime,
      include_qa: FunWithFlags.enabled?(:qa_billing_enabled, for: account)
    )
    |> Enum.map(fn meter ->
      SyncCustomerStripeMeterWorker.new(%{
        customer_id: customer_id,
        event_name: meter.event_name,
        value: meter.value,
        period_start: period_start,
        period_end: period_end
      })
    end)
    |> Oban.insert_all()

    :ok
  end
end
