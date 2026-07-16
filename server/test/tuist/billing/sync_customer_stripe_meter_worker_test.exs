defmodule Tuist.Billing.Workers.SyncCustomerStripeMeterWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.SyncCustomerStripeMeterWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "reports the remote cache hit meter" do
    customer_id = UUIDv7.generate()
    AccountsFixtures.user_fixture(customer_id: customer_id)
    idempotency_key = "#{customer_id}-key"
    usage_date = ~D[2026-07-13]

    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn ^customer_id, ^idempotency_key, ^usage_date ->
      {:ok, :updated}
    end)

    assert :ok == perform(customer_id, "remote_cache_hit", idempotency_key, usage_date)
  end

  test "reports the cache egress meter with the resolved account" do
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)
    idempotency_key = "#{customer_id}-key"
    usage_date = ~D[2026-07-13]

    expect(Tuist.Billing, :update_cache_egress_meter, fn ^account, ^idempotency_key, ^usage_date ->
      {:ok, :updated}
    end)

    assert :ok == perform(customer_id, "cache_egress", idempotency_key, usage_date)
  end

  test "reports the llm token meter" do
    customer_id = UUIDv7.generate()
    AccountsFixtures.user_fixture(customer_id: customer_id)
    idempotency_key = "#{customer_id}-key"
    usage_date = ~D[2026-07-13]

    expect(Tuist.Billing, :update_llm_token_meters, fn ^customer_id, ^idempotency_key, ^usage_date ->
      {:ok, :updated}
    end)

    assert :ok == perform(customer_id, "llm_token", idempotency_key, usage_date)
  end

  test "returns the error so Oban retries when a meter update fails" do
    customer_id = UUIDv7.generate()
    AccountsFixtures.user_fixture(customer_id: customer_id)
    idempotency_key = "#{customer_id}-key"
    usage_date = ~D[2026-07-13]

    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn ^customer_id, ^idempotency_key, ^usage_date ->
      {:error, :meter_not_found}
    end)

    assert {:error, :meter_not_found} == perform(customer_id, "remote_cache_hit", idempotency_key, usage_date)
  end

  defp perform(customer_id, meter, idempotency_key, usage_date) do
    SyncCustomerStripeMeterWorker.perform(%Oban.Job{
      id: 1,
      args: %{
        "customer_id" => customer_id,
        "meter" => meter,
        "idempotency_key" => idempotency_key,
        "usage_date" => Date.to_iso8601(usage_date)
      }
    })
  end
end
