defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorkerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker
  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker
  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "enqueues a meter job for each billable meter when qa billing is enabled (per account)" do
    # Given
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    usage_date = "2026-07-13"
    idempotency_key = "#{customer_id}-#{usage_date}"

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> true end)
    stub(FeatureFlags, :kura_billing_enabled?, fn ^account -> true end)

    # When
    assert :ok ==
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 123,
               args: %{"customer_id" => customer_id, "usage_date" => usage_date}
             })

    # Then
    for meter <- ["remote_cache_hit", "cache_egress", "llm_token"] do
      assert_enqueued(
        worker: SyncCustomerStripeMeterWorker,
        args: %{
          customer_id: customer_id,
          meter: meter,
          idempotency_key: idempotency_key,
          usage_date: usage_date
        }
      )
    end

    assert length(all_enqueued(worker: SyncCustomerStripeMeterWorker)) == 3
  end

  test "does not enqueue the llm meter job when qa billing is disabled for the account" do
    # Given
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    usage_date = "2026-07-13"

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)
    stub(FeatureFlags, :kura_billing_enabled?, fn ^account -> true end)

    # When
    assert :ok ==
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 456,
               args: %{"customer_id" => customer_id, "usage_date" => usage_date}
             })

    # Then
    meters = [worker: SyncCustomerStripeMeterWorker] |> all_enqueued() |> Enum.map(& &1.args["meter"]) |> Enum.sort()
    assert meters == ["cache_egress", "remote_cache_hit"]
  end

  test "does not enqueue cache egress when Kura billing is disabled for the account" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    usage_date = "2026-07-13"

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)
    stub(FeatureFlags, :kura_billing_enabled?, fn ^account -> false end)

    assert :ok ==
             SyncCustomerStripeMetersWorker.perform(%Oban.Job{
               id: 789,
               args: %{"customer_id" => customer_id, "usage_date" => usage_date}
             })

    assert_enqueued(
      worker: SyncCustomerStripeMeterWorker,
      args: %{customer_id: customer_id, meter: "remote_cache_hit", usage_date: usage_date}
    )

    assert length(all_enqueued(worker: SyncCustomerStripeMeterWorker)) == 1
  end
end
