defmodule Tuist.Billing.Workers.SyncCustomerStripeMeterWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker

  test "reports the snapshotted value with the parent period" do
    customer_id = "customer-#{UUIDv7.generate()}"
    event_name = "runner_linux_2_vcpu_8_gb_milliseconds"
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]
    period_start = DateTime.to_unix(period_start_datetime, :microsecond)
    period_end = DateTime.to_unix(period_end_datetime, :microsecond)

    expect(Billing, :report_meter_event, fn ^customer_id,
                                            ^event_name,
                                            750_125,
                                            ^period_start_datetime,
                                            ^period_end_datetime ->
      {:ok, %{id: "meter-event"}}
    end)

    assert {:ok, %{id: "meter-event"}} =
             SyncCustomerStripeMeterWorker.perform(%Oban.Job{
               id: 456,
               args: %{
                 "customer_id" => customer_id,
                 "event_name" => event_name,
                 "value" => 750_125,
                 "period_start" => period_start,
                 "period_end" => period_end
               }
             })
  end
end
