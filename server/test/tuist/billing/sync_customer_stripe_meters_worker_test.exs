defmodule Tuist.Billing.Workers.SyncCustomerStripeMetersWorkerWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Workers.SyncCustomerStripeMetersWorker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "updates all billing meters for the given customer when qa billing is enabled (per account)" do
    # Given
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)

    date = Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")
    idempotency_key = "#{customer_id}-#{date}"

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> true end)

    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn ^customer_id, ^idempotency_key ->
      {:ok, :updated}
    end)

    expect(Tuist.Billing, :update_llm_token_meters, fn ^customer_id, ^idempotency_key ->
      {:ok, :updated}
    end)

    expect(Tuist.Billing, :update_namespace_usage_meter, fn ^customer_id, ^idempotency_key ->
      {:ok, :updated}
    end)

    # When/Then
    SyncCustomerStripeMetersWorker.perform(%Oban.Job{
      id: 123,
      args: %{"customer_id" => customer_id}
    })
  end

  test "does not update llm meters when qa billing is disabled for the account" do
    # Given
    customer_id = UUIDv7.generate()
    %{account: account} = AccountsFixtures.user_fixture(customer_id: customer_id)

    date = Timex.format!(Tuist.Time.utc_now(), "{YYYY}.{0M}.{D}")
    idempotency_key = "#{customer_id}-#{date}"

    stub(FunWithFlags, :enabled?, fn :qa_billing_enabled, [for: ^account] -> false end)

    expect(Tuist.Billing, :update_remote_cache_hit_meter, fn ^customer_id, ^idempotency_key ->
      {:ok, :updated}
    end)

    # Ensure namespace usage meter is not called either
    stub(Tuist.Billing, :update_namespace_usage_meter, fn ^customer_id, ^idempotency_key ->
      flunk("update_namespace_usage_meter should not be called when qa billing is disabled")
    end)

    # When/Then (no expectation set on update_llm_token_meters, so it must not be called)
    SyncCustomerStripeMetersWorker.perform(%Oban.Job{
      id: 456,
      args: %{"customer_id" => customer_id}
    })
  end
end
