defmodule Tuist.Kura.AccountPoliciesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Kura.Server
  alias Tuist.Kura.Telemetry
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

    test "defaults a paid account that allows every region to United States East" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :pro, service_region: "us-east"}}
    end

    test "keeps a paid account that allows every region in the region it already runs in" do
      # The default is for accounts with no instance. Applying it to one that is
      # already being served elsewhere would cold-provision a second instance in
      # the default region and strand the first, which on a plan that is never
      # archived has no reclamation path.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      live_instance(account, "eu-central")

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "eu-central"}}
    end

    test "does not resolve a paid account into its private runner-cache region" do
      # A runner-cache instance is provisioned by a separate identity rule, is
      # never CLI-facing, and lives in a region the lifecycle never iterates.
      # Resolving there would leave the account with no developer-facing cache
      # and nothing provisioning one, which is the failure this change removes.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      live_instance(account, "scw-fr-par-runners")

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "us-east"}}
    end

    test "resolves a paid account to its public instance, not its runner cache" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      live_instance(account, "scw-fr-par-runners", age_days: 200)
      live_instance(account, "eu-central", age_days: 10)

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "eu-central"}}
    end

    test "resolves a paid account holding several instances to its oldest" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      live_instance(account, "us-west", age_days: 200)
      live_instance(account, "eu-central", age_days: 10)

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "us-west"}}
    end

    test "ignores a torn-down instance when defaulting a paid account" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      live_instance(account, "eu-central", status: :archived)

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :pro, service_region: "us-east"}}
    end

    test "prefers an explicit assignment over the region an account runs in" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      live_instance(account, "us-east")

      assert {:ok, _assignment} =
               AccountPolicies.assign_service_region(
                 account,
                 "eu-central",
                 AccountsFixtures.user_fixture(),
                 "Customer residency requirement"
               )

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "eu-central"}}
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

      defaulted = organization_account()
      BillingFixtures.subscription_fixture(account_id: defaulted.id, plan: :pro)

      running = organization_account()
      BillingFixtures.subscription_fixture(account_id: running.id, plan: :enterprise)
      live_instance(running, "us-west")

      assigned = organization_account()
      BillingFixtures.subscription_fixture(account_id: assigned.id, plan: :pro)

      assert {:ok, _} =
               AccountPolicies.assign_service_region(
                 assigned,
                 "eu-central",
                 AccountsFixtures.user_fixture(),
                 "Customer residency requirement"
               )

      accounts =
        Enum.map([air, restricted, defaulted, running, assigned], &Repo.preload(&1, :subscriptions))

      assert AccountPolicies.resolve_all(accounts) ==
               Map.new(accounts, &{&1.id, AccountPolicies.resolve(&1)})
    end

    test "falls back to Air when a paid subscription is inactive" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise, status: "canceled")

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :air, service_region: "us-east"}}
    end

    test "refuses a Europe-restricted Air account until the European Air pool is deployed" do
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

    test "assigns United States West, which no storage-region preference derives to" do
      # `accounts.region` is all | europe | usa; `usa` derives to us-east and
      # `all` defaults to it, so an assignment is the only route to us-west.
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert {:ok, assignment} =
               AccountPolicies.assign_service_region(account, "us-west", actor, "Latency")

      assert assignment.service_region == "us-west"

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "us-west"}}
    end

    test "rejects the plan-scoped Air pool as an assignment target" do
      # A single best-effort box with no recovery machine, sized for Air. A paid
      # account pinned there would undo the tier separation it exists to keep.
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert AccountPolicies.assign_service_region(
               account,
               "eu-air",
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

  defp live_instance(account, region, opts \\ []) do
    inserted_at =
      DateTime.add(DateTime.utc_now(), -Keyword.get(opts, :age_days, 30) * 86_400, :second)

    %Server{
      account_id: account.id,
      region: region,
      status: Keyword.get(opts, :status, :active),
      url: "https://#{account.name}-#{region}-1.kura.tuist.dev",
      current_image_tag: "sha-abcdef123456",
      provisioner_node_ref: "kura-#{account.id}-#{region}"
    }
    |> Repo.insert!()
    |> Ecto.Changeset.change(%{inserted_at: inserted_at, updated_at: inserted_at})
    |> Repo.update!()
  end

  defp deploy_regions(region_ids) do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> region_ids end)
  end

  describe "the Air region" do
    test "is United States East for an account that states no storage region" do
      assert Environment.kura_air_region(:all) == "us-east"
      assert Environment.kura_air_region(:usa) == "us-east"
    end

    test "is its own European pool for an account that chose Europe" do
      assert Environment.kura_air_region(:europe) == "eu-air"
    end

    test "is where an Air account resolves" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      stub(Environment, :kura_air_region, fn :all -> "ca-east" end)

      assert {:ok, %{plan: :air, service_region: "ca-east"}} = AccountPolicies.resolve(account)
    end

    test "does not move a paid account restricted to a storage region" do
      # Where the free tier runs is a deployment decision. A paid account that
      # chose Europe or the USA chose it, and no deployment setting relocates
      # it.
      account = update_region!(organization_account(), :europe)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      stub(Environment, :kura_air_region, fn :europe -> "ca-east" end)

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "eu-central"}}
    end

    test "keeps a Europe-restricted Air account in Europe once the pool is deployed" do
      account = update_region!(organization_account(), :europe)

      deploy_regions(["us-east", "eu-central", "eu-air"])

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :air, service_region: "eu-air"}}
    end

    test "never places a Europe-restricted Air account in the United States" do
      # "Storage region" names module cache binaries, which is what a Kura
      # instance holds, so an account that chose Europe is refused rather than
      # served from the Air pool that happens to be running.
      account = update_region!(organization_account(), :europe)

      deploy_regions(["us-east", "eu-central"])

      assert AccountPolicies.resolve(account) == {:error, :service_region_unavailable}
    end
  end

  describe "refusal telemetry" do
    test "counts a plan with no Kura pool behind it" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :open_source)

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [Telemetry.event_name_resolution_refused()])

      assert AccountPolicies.resolve(account) == {:error, :plan_not_supported}

      assert_receive {[:tuist, :kura, :lifecycle, :resolution_refused], ^event_ref, %{count: 1},
                      %{plan: "open_source", reason: "plan_not_supported"}}
    end

    test "counts an Air account whose storage region has no Air pool deployed" do
      account = update_region!(organization_account(), :europe)

      deploy_regions(["us-east"])

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [Telemetry.event_name_resolution_refused()])

      assert AccountPolicies.resolve(account) == {:error, :service_region_unavailable}

      assert_receive {[:tuist, :kura, :lifecycle, :resolution_refused], ^event_ref, %{count: 1},
                      %{plan: "air", reason: "service_region_unavailable"}}
    end

    test "counts every refusal in a batch" do
      first = organization_account()
      BillingFixtures.subscription_fixture(account_id: first.id, plan: :open_source)

      second = organization_account()
      BillingFixtures.subscription_fixture(account_id: second.id, plan: :open_source)

      accounts = Enum.map([first, second], &Repo.preload(&1, :subscriptions))

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [Telemetry.event_name_resolution_refused()])

      AccountPolicies.resolve_all(accounts)

      for _account <- accounts do
        assert_receive {[:tuist, :kura, :lifecycle, :resolution_refused], ^event_ref, %{count: 1},
                        %{plan: "open_source", reason: "plan_not_supported"}}
      end
    end

    test "leaves a resolved account uncounted" do
      account = organization_account()

      event_ref =
        :telemetry_test.attach_event_handlers(self(), [Telemetry.event_name_resolution_refused()])

      assert {:ok, %{plan: :air}} = AccountPolicies.resolve(account)

      refute_receive {_event_name, ^event_ref, _measurements, _metadata}
    end
  end
end
