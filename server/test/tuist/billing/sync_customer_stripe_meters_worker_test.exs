defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorkerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "enqueues a meter job for each billable meter when qa billing is enabled (per account)" do
    # Given
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)

    date = Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")
    idempotency_key = "#{customer_id}-#{date}"

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> true end)

    # When
    assert :ok ==
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 123,
               args: %{"customer_id" => customer_id}
             })

    # Then
    for meter <- ["remote_cache_hit", "cache_egress", "llm_token"] do
      assert_enqueued(
        worker: SyncCustomerStripeMeterWorker,
        args: %{customer_id: customer_id, meter: meter, idempotency_key: idempotency_key}
      )
    end

    assert length(all_enqueued(worker: SyncCustomerStripeMeterWorker)) == 3
  end

  test "does not enqueue the llm meter job when qa billing is disabled for the account" do
    # Given
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    # When
    assert :ok ==
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 456,
               args: %{"customer_id" => customer_id}
             })

    # Then
    meters = [worker: SyncCustomerStripeMeterWorker] |> all_enqueued() |> Enum.map(& &1.args["meter"]) |> Enum.sort()
    assert meters == ["cache_egress", "remote_cache_hit"]
  end
end
