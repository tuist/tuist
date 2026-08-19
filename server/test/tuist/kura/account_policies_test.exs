defmodule Tuist.Kura.AccountPoliciesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  describe "resolve/1" do
    test "resolves an account without a subscription to Air in United States East" do
      account = organization_account()

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :air, service_region: "us-east"}}
    end

    test "resolves a personal paid account restricted to the United States" do
      account = update_region!(personal_account(), :usa)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :pro, service_region: "us-east"}}
    end

    test "resolves an Enterprise account restricted to Europe" do
      account = update_region!(organization_account(), :europe)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "eu-central"}}
    end

    test "requires an explicit assignment for a paid account that allows every region" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      assert AccountPolicies.resolve(account) == {:error, :service_region_unassigned}
    end

    test "uses the current explicit assignment for a paid account that allows every region" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      assert {:ok, _assignment} =
               AccountPolicies.assign_service_region(
                 account,
                 "eu-central",
                 actor,
                 "Customer residency requirement"
               )

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :pro, service_region: "eu-central"}}
    end

    test "resolve_all/1 matches resolve/1 across a mixed batch" do
      air = organization_account()

      restricted = update_region!(organization_account(), :europe)
      BillingFixtures.subscription_fixture(account_id: restricted.id, plan: :pro)

      unassigned = organization_account()
      BillingFixtures.subscription_fixture(account_id: unassigned.id, plan: :pro)

      assigned = organization_account()
      BillingFixtures.subscription_fixture(account_id: assigned.id, plan: :pro)

      assert {:ok, _} =
               AccountPolicies.assign_service_region(
                 assigned,
                 "eu-central",
                 AccountsFixtures.user_fixture(),
                 "Customer residency requirement"
               )

      accounts = Enum.map([air, restricted, unassigned, assigned], &Repo.preload(&1, :subscriptions))

      assert AccountPolicies.resolve_all(accounts) ==
               Map.new(accounts, &{&1.id, AccountPolicies.resolve(&1)})
    end

    test "falls back to Air when a paid subscription is inactive" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise, status: "canceled")

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :air, service_region: "us-east"}}
    end

    test "keeps a Europe-restricted Air account on the fallback route" do
      account = update_region!(organization_account(), :europe)

      assert AccountPolicies.resolve(account) == {:error, :service_region_unavailable}
    end

    test "does not include open-source accounts in the first rollout" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :open_source)

      assert AccountPolicies.resolve(account) == {:error, :plan_not_supported}
    end
  end

  describe "assign_service_region/4" do
    test "versions assignments and retains actor, reason, and superseded history" do
      account = organization_account()
      first_actor = AccountsFixtures.user_fixture()
      second_actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert {:ok, first} =
               AccountPolicies.assign_service_region(
                 account,
                 "us-east",
                 first_actor,
                 "Most cache demand is in the United States"
               )

      assert first.version == 1
      assert first.assigned_by_user_id == first_actor.id
      assert is_nil(first.superseded_at)

      assert {:ok, second} =
               AccountPolicies.assign_service_region(
                 account,
                 "eu-central",
                 second_actor,
                 "Customer moved the workload to Europe"
               )

      assert second.version == 2
      assert second.assigned_by_user_id == second_actor.id
      assert is_nil(second.superseded_at)

      assert [current, superseded] = AccountPolicies.list_service_region_history(account)
      assert current.id == second.id
      assert superseded.id == first.id
      assert superseded.superseded_at

      assert %AccountRegionPolicy{id: current_id} =
               AccountPolicies.current_service_region_assignment(account)

      assert current_id == second.id
    end

    test "rejects assignments when the account region already determines placement" do
      account = update_region!(organization_account(), :usa)
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      assert AccountPolicies.assign_service_region(
               account,
               "us-east",
               actor,
               "Already determined"
             ) == {:error, :service_region_is_derived}
    end

    test "rejects assignments for Air accounts" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()

      assert AccountPolicies.assign_service_region(
               account,
               "us-east",
               actor,
               "Air placement"
             ) == {:error, :plan_not_supported}
    end

    test "rejects regions outside the first rollout" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert AccountPolicies.assign_service_region(
               account,
               "us-west",
               actor,
               "Unsupported placement"
             ) == {:error, :service_region_unavailable}
    end
  end

  describe "restore_service_region/4" do
    test "restores a historical region as a new version" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      {:ok, first} =
        AccountPolicies.assign_service_region(account, "us-east", actor, "Initial assignment")

      {:ok, _second} =
        AccountPolicies.assign_service_region(account, "eu-central", actor, "Regional move")

      assert {:ok, restored} =
               AccountPolicies.restore_service_region(
                 account,
                 first.version,
                 actor,
                 "Rollback regional move"
               )

      assert restored.version == 3
      assert restored.service_region == "us-east"
      assert restored.reason == "Rollback regional move"
    end

    test "returns an error for an unknown historical version" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()

      assert AccountPolicies.restore_service_region(account, 99, actor, "Unknown version") ==
               {:error, :assignment_not_found}
    end
  end

  defp organization_account do
    AccountsFixtures.organization_fixture(preload: [:account]).account
  end

  defp personal_account do
    AccountsFixtures.user_fixture(preload: [:account]).account
  end

  defp update_region!(account, region) do
    {:ok, account} = Accounts.update_account(account, %{region: region})
    account
  end

  describe "the Air region" do
    test "is United States East unless the deployment names another" do
      assert Environment.kura_air_region() == "us-east"
    end

    test "is where an Air account resolves" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      stub(Environment, :kura_air_region, fn -> "ca-east" end)

      assert {:ok, %{plan: :air, service_region: "ca-east"}} = AccountPolicies.resolve(account)
    end

    test "does not move a paid account restricted to a storage region" do
      # Where the free tier runs is a deployment decision. A paid account that
      # chose Europe or the USA chose it, and no deployment setting relocates
      # it.
      account = update_region!(organization_account(), :europe)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      stub(Environment, :kura_air_region, fn -> "ca-east" end)

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "eu-central"}}
    end

    test "does not turn a restricted Air account into a resolvable one" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)
      {:ok, account} = Accounts.update_account(account, %{region: :europe})

      stub(Environment, :kura_air_region, fn -> "eu-central" end)

      assert {:error, :service_region_unavailable} = AccountPolicies.resolve(account)
    end
  end
end
