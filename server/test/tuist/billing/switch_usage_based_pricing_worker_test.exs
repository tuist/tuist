defmodule Tuist.Billing.Workers.SwitchUsageBasedPricingWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Billing
  alias Tuist.Billing.Workers.SwitchUsageBasedPricingWorker
  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    account = Accounts.get_account_from_user(AccountsFixtures.user_fixture(customer_id: "customer_id"))

    stub(Billing, :usage_meter_price_ids, fn -> ["meter.egress", "meter.requests", "meter.tests"] end)
    stub(Billing, :accounts_with_pro_subscriptions, fn -> [account] end)
    stub(FeatureFlags, :usage_based_pricing_switch_enabled?, fn _account -> true end)

    %{account: account}
  end

  test "switches an account the flag covers", %{account: account} do
    account_id = account.id

    expect(Billing, :switch_to_usage_based_pricing, fn %{id: ^account_id} -> {:ok, :switched} end)

    assert SwitchUsageBasedPricingWorker.perform(%Oban.Job{args: %{}}) == :ok
  end

  test "switches nobody while the meters are still reporting-only" do
    stub(Billing, :usage_meter_price_ids, fn -> [] end)
    reject(&Billing.switch_to_usage_based_pricing/1)

    assert SwitchUsageBasedPricingWorker.perform(%Oban.Job{args: %{}}) == :ok
  end

  test "switches nobody while the flag is off for the account" do
    stub(FeatureFlags, :usage_based_pricing_switch_enabled?, fn _account -> false end)
    reject(&Billing.switch_to_usage_based_pricing/1)

    assert SwitchUsageBasedPricingWorker.perform(%Oban.Job{args: %{}}) == :ok
  end

  test "reports the accounts it could not switch", %{account: account} do
    stub(Billing, :switch_to_usage_based_pricing, fn _account -> {:error, :no_subscription} end)

    assert {:error, message} = SwitchUsageBasedPricingWorker.perform(%Oban.Job{args: %{}})
    assert message =~ "#{account.id}"
    assert message =~ "no_subscription"
  end
end
