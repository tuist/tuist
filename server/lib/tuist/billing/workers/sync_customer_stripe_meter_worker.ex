defmodule Tuist.Billing.Workers.SyncCustomerStripeMeterWorker do
  @moduledoc """
  Reports one snapshotted customer meter value for the billing period
  chosen by the parent worker.
  """
  use Oban.Worker

  alias Tuist.Billing

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "customer_id" => customer_id,
          "event_name" => event_name,
          "value" => value,
          "period_start" => period_start,
          "period_end" => period_end
        }
      }) do
    period_start_datetime = DateTime.from_unix!(period_start, :microsecond)
    period_end_datetime = DateTime.from_unix!(period_end, :microsecond)

    if Tuist.Environment.error_tracking_enabled?() do
      Sentry.Context.set_extra_context(%{
        customer_id: customer_id,
        event_name: event_name,
        period_start: period_start_datetime,
        period_end: period_end_datetime
      })
    end

    Billing.report_meter_event(
      customer_id,
      event_name,
      value,
      period_start_datetime,
      period_end_datetime
    )
  end
end
