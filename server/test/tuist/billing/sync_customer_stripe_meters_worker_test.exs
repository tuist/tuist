defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing
  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "enqueues one child job per snapshotted meter with the parent period" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]
    period_start = DateTime.to_unix(period_start_datetime, :microsecond)
    period_end = DateTime.to_unix(period_end_datetime, :microsecond)

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> true end)

    expect(Billing, :customer_meter_values, fn ^account,
                                               ^period_start_datetime,
                                               ^period_end_datetime,
                                               [include_qa: true] ->
      [
        %{event_name: "remote_cache_hit", value: 10},
        %{event_name: "llm_input_token", value: 20},
        %{event_name: "runner_macos_compute_unit_milliseconds", value: 30}
      ]
    end)

    assert :ok =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 123,
               args: %{
                 "customer_id" => customer_id,
                 "period_start" => period_start,
                 "period_end" => period_end
               }
             })

    jobs = all_enqueued(worker: SyncCustomerStripeMeterWorker)
    assert length(jobs) == 3

    assert jobs |> Enum.map(& &1.args["event_name"]) |> Enum.sort() == [
             "llm_input_token",
             "remote_cache_hit",
             "runner_macos_compute_unit_milliseconds"
           ]

    assert Enum.all?(jobs, fn job ->
             job.args["period_start"] == period_start and job.args["period_end"] == period_end
           end)
  end

  test "snapshots each side of a renewal separately when the day straddles one" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]
    boundary = ~U[2026-07-16 09:30:00Z]

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    stub(Billing, :usage_windows, fn ^account, ^period_start_datetime, ^period_end_datetime ->
      {:ok, [{period_start_datetime, boundary}, {boundary, period_end_datetime}]}
    end)

    stub(Billing, :customer_meter_values, fn ^account, window_start, window_end, [include_qa: false] ->
      # Distinguish the two windows so the enqueued values prove each was
      # snapshotted against its own bounds rather than the whole day.
      value = if window_start == period_start_datetime and window_end == boundary, do: 10, else: 20
      [%{event_name: "remote_cache_hit", value: value}]
    end)

    assert :ok =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 789,
               args: %{
                 "customer_id" => customer_id,
                 "period_start" => DateTime.to_unix(period_start_datetime, :microsecond),
                 "period_end" => DateTime.to_unix(period_end_datetime, :microsecond)
               }
             })

    jobs = all_enqueued(worker: SyncCustomerStripeMeterWorker)

    assert jobs
           |> Enum.map(&{&1.args["value"], &1.args["period_start"], &1.args["period_end"]})
           |> Enum.sort() == [
             {10, DateTime.to_unix(period_start_datetime, :microsecond), DateTime.to_unix(boundary, :microsecond)},
             {20, DateTime.to_unix(boundary, :microsecond), DateTime.to_unix(period_end_datetime, :microsecond)}
           ]
  end

  test "snoozes without noise when boundary discovery hits a transient Stripe network blip" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    stub(Billing, :customer_meter_values, fn ^account, _window_start, _window_end, [include_qa: false] ->
      [%{event_name: "remote_cache_hit", value: 7}]
    end)

    stub(Billing, :usage_windows, fn ^account, ^period_start_datetime, ^period_end_datetime ->
      {:error, %Stripe.Error{source: :network, code: :network_code, message: "boom"}}
    end)

    # `{:snooze, _}` reschedules without logging at :error, so a hackney
    # blip doesn't fire a Sentry event on every retry attempt.
    assert {:snooze, seconds} =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 790,
               args: %{
                 "customer_id" => customer_id,
                 "period_start" => DateTime.to_unix(period_start_datetime, :microsecond),
                 "period_end" => DateTime.to_unix(period_end_datetime, :microsecond)
               }
             })

    assert is_integer(seconds) and seconds > 0
    assert all_enqueued(worker: SyncCustomerStripeMeterWorker) == []
  end

  test "propagates non-network boundary-discovery errors so Oban's normal retry surfaces them" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]
    error = %Stripe.Error{source: :stripe, code: :api_error, message: "boom"}

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    stub(Billing, :customer_meter_values, fn ^account, _window_start, _window_end, [include_qa: false] ->
      [%{event_name: "remote_cache_hit", value: 7}]
    end)

    stub(Billing, :usage_windows, fn ^account, ^period_start_datetime, ^period_end_datetime ->
      {:error, error}
    end)

    assert {:error, ^error} =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 790,
               args: %{
                 "customer_id" => customer_id,
                 "period_start" => DateTime.to_unix(period_start_datetime, :microsecond),
                 "period_end" => DateTime.to_unix(period_end_datetime, :microsecond)
               }
             })

    assert all_enqueued(worker: SyncCustomerStripeMeterWorker) == []
  end

  test "handles pre-deploy jobs that carry only the customer id" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    expect(Billing, :customer_meter_values, fn ^account, %DateTime{}, %DateTime{}, [include_qa: false] ->
      [%{event_name: "remote_cache_hit", value: 5}]
    end)

    assert :ok =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 456,
               args: %{"customer_id" => customer_id}
             })

    [job] = all_enqueued(worker: SyncCustomerStripeMeterWorker)
    assert job.args["event_name"] == "remote_cache_hit"
    assert is_integer(job.args["period_start"])
    assert is_integer(job.args["period_end"])
    assert job.args["period_end"] > job.args["period_start"]
  end

  test "skips boundary discovery when the day earned nothing" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    expect(Billing, :customer_meter_values, fn ^account,
                                               ^period_start_datetime,
                                               ^period_end_datetime,
                                               [include_qa: false] ->
      []
    end)

    # Boundary discovery costs a Stripe request, and the overwhelming
    # majority of billable customers earn nothing on a given day. Splitting
    # a window that has no usage to attribute to either side changes
    # nothing, so the request is not worth spending.
    reject(&Billing.usage_windows/3)

    assert :ok =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 791,
               args: %{
                 "customer_id" => customer_id,
                 "period_start" => DateTime.to_unix(period_start_datetime, :microsecond),
                 "period_end" => DateTime.to_unix(period_end_datetime, :microsecond)
               }
             })

    assert all_enqueued(worker: SyncCustomerStripeMeterWorker) == []
  end

  test "snapshots usage once when no boundary splits the day" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    period_start_datetime = ~U[2026-07-16 00:00:00.000000Z]
    period_end_datetime = ~U[2026-07-17 00:00:00.000000Z]

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    stub(Billing, :usage_windows, fn ^account, ^period_start_datetime, ^period_end_datetime ->
      {:ok, [{period_start_datetime, period_end_datetime}]}
    end)

    # Exactly one invocation: the unsplit window is the day the gate
    # already measured, and each snapshot aggregates over ClickHouse.
    expect(Billing, :customer_meter_values, 1, fn ^account,
                                                  ^period_start_datetime,
                                                  ^period_end_datetime,
                                                  [include_qa: false] ->
      [%{event_name: "remote_cache_hit", value: 12}]
    end)

    assert :ok =
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 792,
               args: %{
                 "customer_id" => customer_id,
                 "period_start" => DateTime.to_unix(period_start_datetime, :microsecond),
                 "period_end" => DateTime.to_unix(period_end_datetime, :microsecond)
               }
             })

    [job] = all_enqueued(worker: SyncCustomerStripeMeterWorker)
    assert job.args["value"] == 12
    assert job.args["period_start"] == DateTime.to_unix(period_start_datetime, :microsecond)
    assert job.args["period_end"] == DateTime.to_unix(period_end_datetime, :microsecond)
  end
end
