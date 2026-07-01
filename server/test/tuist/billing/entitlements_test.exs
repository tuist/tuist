defmodule Tuist.Billing.EntitlementsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Billing.Entitlements
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  describe "allows?/2 — :github_enterprise_server on the hosted Tuist server" do
    setup do
      stub(Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "true when the active subscription is enterprise" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert Entitlements.allows?(account, :github_enterprise_server)
    end

    test "false when the active subscription is pro" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      refute Entitlements.allows?(account, :github_enterprise_server)
    end

    test "false when the active subscription is air" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :air)

      refute Entitlements.allows?(account, :github_enterprise_server)
    end

    test "false when there is no active subscription (treated as :air)" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      refute Entitlements.allows?(account, :github_enterprise_server)
    end

    test "ignores cancelled enterprise subscriptions" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise, status: "canceled")

      refute Entitlements.allows?(account, :github_enterprise_server)
    end
  end

  describe "allows?/2 — hosted features that are Enterprise only by default" do
    setup do
      stub(Environment, :tuist_hosted?, fn -> true end)
      :ok
    end

    test "true for dedicated Kura gateways when the active subscription is enterprise" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert Entitlements.allows?(account, :dedicated_kura_gateway)
    end

    test "false for dedicated Kura gateways when there is no active subscription" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      refute Entitlements.allows?(account, :dedicated_kura_gateway)
    end

    test "true for self-hosted cache when the active subscription is enterprise" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert Entitlements.allows?(account, :self_hosted_cache)
    end

    test "false for self-hosted cache when the active subscription is not enterprise" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      refute Entitlements.allows?(account, :self_hosted_cache)
    end

    test "false for unknown features when the active subscription is not enterprise" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      refute Entitlements.allows?(account, :unknown_hosted_feature)
    end
  end

  describe "allows?/2 — self-hosted Tuist" do
    setup do
      stub(Environment, :tuist_hosted?, fn -> false end)
      :ok
    end

    test "self-hosted deployments grant every feature unconditionally" do
      account = AccountsFixtures.organization_fixture(preload: [:account]).account

      assert Entitlements.allows?(account, :github_enterprise_server)
    end

    test "tolerates a nil account" do
      assert Entitlements.allows?(nil, :github_enterprise_server)
    end
  end
end
