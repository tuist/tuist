defmodule Tuist.FeatureFlagsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias TuistTestSupport.Fixtures.AccountsFixtures

  test "requires the account-scoped Kura billing flag on hosted deployments" do
    %{account: account} = AccountsFixtures.user_fixture()

    stub(Environment, :tuist_hosted?, fn -> true end)

    expect(FunWithFlags, :enabled?, fn :kura_billing, [for: ^account] -> true end)

    assert FeatureFlags.kura_billing_enabled?(account)
  end

  test "keeps Kura billing disabled on customer-operated deployments" do
    %{account: account} = AccountsFixtures.user_fixture()

    stub(Environment, :tuist_hosted?, fn -> false end)
    reject(&FunWithFlags.enabled?/2)

    refute FeatureFlags.kura_billing_enabled?(account)
  end
end
