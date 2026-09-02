defmodule Tuist.Kura.AccountPoliciesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Kura.Origins
  alias Tuist.Kura.PlacerRegions
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
      serving(["us-east", "eu-central"])
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
      serving(["eu-central"])
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

    test "refuses a Europe-restricted Air account until a deployment serves Air in Europe" do
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

    test "admits an assignment to any region the account's storage region allows" do
      # A storage region is a boundary, not a placement: "United States" is
      # kept by both American regions, and pinning to the nearer one breaks
      # nothing the account was promised.
      account = update_region!(organization_account(), :usa)
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      deploy_regions(["us-east", "us-west"])

      assert {:ok, %AccountRegionPolicy{service_region: "us-west"}} =
               AccountPolicies.assign_service_region(account, "us-west", actor, "Developers are on the west coast")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "us-west"}}
    end

    test "rejects an assignment outside the account's storage region" do
      account = update_region!(organization_account(), :usa)
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)

      assert AccountPolicies.assign_service_region(
               account,
               "eu-central",
               actor,
               "Outside the promise"
             ) == {:error, :service_region_outside_residency}
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
      serving(["us-east", "us-west"])
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert {:ok, assignment} =
               AccountPolicies.assign_service_region(account, "us-west", actor, "Latency")

      assert assignment.service_region == "us-west"

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "us-west"}}
    end

    test "assigns Asia Pacific Southeast, which no storage-region preference derives to" do
      # Same shape as us-west: `accounts.region` is all | europe | usa, none of
      # which name Asia Pacific, so an assignment is the only route there. The
      # assignment is recordable before the Singapore box exists — what
      # TUIST_KURA_AVAILABLE_REGIONS gates is serving the region, not naming it.
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert {:ok, assignment} =
               AccountPolicies.assign_service_region(
                 account,
                 "ap-southeast",
                 actor,
                 "Developers are in Singapore; US East is a ~200ms round trip"
               )

      assert assignment.service_region == "ap-southeast"
      assert assignment.version == 1

      # Persisted, not just validated: the CHECK constraint on
      # kura_account_region_policies has to admit the region too.
      assert %AccountRegionPolicy{service_region: "ap-southeast"} =
               Repo.get(AccountRegionPolicy, assignment.id)

      assert AccountPolicies.current_service_region_assignment(account).service_region ==
               "ap-southeast"

      # The second gate. Recording the placement does not make it resolvable:
      # no deployment serves Singapore yet, so resolution refuses rather than
      # handing back a region nothing provisions in. Resolving it here would
      # record demand under a region `Lifecycle.lifecycle_regions/0` never
      # iterates and report the account as provisioning forever.
      assert AccountPolicies.resolve(account) == {:error, :service_region_unavailable}

      # And the assignment is untouched by the refusal, so the region starts
      # resolving the moment the box exists and the gate names it — no
      # reassignment, no operator action.
      serving(["us-east", "ap-southeast"])

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "ap-southeast"}}

      assert AccountPolicies.current_service_region_assignment(account).version == 1
    end

    test "rejects a region outside the assignable set" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert AccountPolicies.assign_service_region(
               account,
               "ca-east",
               actor,
               "Unsupported placement"
             ) == {:error, :service_region_unavailable}
    end
  end

  describe "Asia Pacific Southeast is assignment-only" do
    test "no storage-region preference derives to it on any plan" do
      # The point of the region: nothing places an account there implicitly, so
      # a reader looking for a derivation rule finds this instead. Every
      # accounts.region value crossed with every plan that resolves at all.
      for region <- [:all, :europe, :usa],
          plan <- [:air, :pro, :enterprise] do
        account = update_region!(organization_account(), region)

        if plan != :air do
          BillingFixtures.subscription_fixture(account_id: account.id, plan: plan)
        end

        case AccountPolicies.resolve(account) do
          {:ok, %{service_region: service_region}} ->
            refute service_region == "ap-southeast",
                   "region=#{region} plan=#{plan} derived to ap-southeast"

          {:error, _reason} ->
            :ok
        end
      end
    end

    test "an account that named a country group cannot be assigned there either" do
      # Singapore keeps no promise made to an account that chose the United
      # States, so the assignment is refused rather than quietly overriding the
      # storage region the account chose.
      account = update_region!(organization_account(), :usa)
      actor = AccountsFixtures.user_fixture()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)

      assert AccountPolicies.assign_service_region(
               account,
               "ap-southeast",
               actor,
               "Developers are in Singapore"
             ) == {:error, :service_region_outside_residency}

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :enterprise, service_region: "us-east"}}
    end

    test "an Air account cannot reach it, because Air never reads an assignment" do
      account = organization_account()
      actor = AccountsFixtures.user_fixture()

      assert AccountPolicies.assign_service_region(
               account,
               "ap-southeast",
               actor,
               "Developers are in Singapore"
             ) == {:error, :plan_not_supported}

      assert AccountPolicies.resolve(account) ==
               {:ok, %{plan: :air, service_region: "us-east"}}
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

  # An assignment only resolves where the deployment serves the region, so a
  # test asserting a resolved assignment has to name a deployment that serves
  # it. Test env otherwise exposes the local controller region alone.
  defp serving(region_ids) do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> region_ids end)
  end

  defp seed_origin(account, origin) do
    Origins.upsert_many([
      %{account_id: account.id, origin: origin, date: Date.utc_today(), run_count: 5, demand_count: 1}
    ])
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

  describe "placement by origin" do
    test "places a new account in the region nearest its traffic" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east", "eu-central"])
      seed_origin(account, "FR")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "eu-central"}}
    end

    test "leaves an account already running where it is" do
      # Moving a running account is a relocation, which is a decision taken on
      # a window of evidence rather than on the request in hand.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      serving(["us-east", "eu-central"])
      live_instance(account, "us-east")
      seed_origin(account, "FR")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :enterprise, service_region: "us-east"}}
    end

    test "a placement decision outranks where the account is already running" do
      # Which is exactly what an applied relocation is: a decision to stop
      # being sticky.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      serving(["us-east", "eu-central"])
      live_instance(account, "us-east")
      {:ok, _row} = PlacerRegions.put_primary(account, "eu-central")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :enterprise, service_region: "eu-central"}}
    end

    test "an operator pin outranks a placement decision" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      serving(["us-east", "eu-central"])
      {:ok, _row} = PlacerRegions.put_primary(account, "eu-central")

      {:ok, _assignment} =
        AccountPolicies.assign_service_region(account, "us-east", AccountsFixtures.user_fixture(), "Contractual")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :enterprise, service_region: "us-east"}}
    end

    test "stops honouring an operator pin the account's storage region no longer allows" do
      # The pin was valid when it was made; the customer narrowed the promise
      # afterwards. Honouring it would keep serving them from a region they
      # have just said their data may not live in.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      serving(["us-east", "eu-central"])

      {:ok, _assignment} =
        AccountPolicies.assign_service_region(account, "eu-central", AccountsFixtures.user_fixture(), "Contractual")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :enterprise, service_region: "eu-central"}}

      account = update_region!(account, :usa)

      assert {:ok, %{service_region: region}} = AccountPolicies.resolve(account)
      assert region in ["us-east", "us-west"]
    end

    test "never places outside the account's storage region" do
      # Residency is a compliance boundary, so traffic cannot argue an account
      # across it however one-sided the traffic is.
      account = update_region!(organization_account(), :usa)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east", "us-west", "eu-central"])
      seed_origin(account, "FR")

      assert {:ok, %{service_region: region}} = AccountPolicies.resolve(account)
      assert region in ["us-east", "us-west"]
    end

    test "chooses between two regions the same storage region admits" do
      # The gap this closes: United States West used to be reachable only by an
      # operator assigning it account by account.
      account = update_region!(organization_account(), :usa)
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east", "us-west"])
      seed_origin(account, "US-OR")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "us-west"}}
    end

    test "falls back to the default when nothing could be attributed" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east", "eu-central"])

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "us-east"}}
    end

    test "does not place into a region the deployment does not serve" do
      # Resolving into a region the lifecycle never iterates would record demand
      # nothing provisions against and report the account as provisioning
      # forever.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east"])
      seed_origin(account, "FR")

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "us-east"}}
    end

    test "runs outweigh resolutions when the two disagree" do
      # Resolutions are cached by the client for an hour and refreshed by an
      # idle launch agent; runs are what the thresholds are expressed in.
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east", "eu-central"])

      Origins.upsert_many([
        %{account_id: account.id, origin: "FR", date: Date.utc_today(), run_count: 10, demand_count: 0},
        %{account_id: account.id, origin: "US-VA", date: Date.utc_today(), run_count: 0, demand_count: 99}
      ])

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :pro, service_region: "eu-central"}}
    end

    test "resolves the same answer in batch as it does one at a time" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :pro)
      serving(["us-east", "eu-central"])
      seed_origin(account, "FR")

      assert AccountPolicies.resolve_all([account]) == %{account.id => AccountPolicies.resolve(account)}
    end
  end

  describe "serving_regions/1" do
    test "is the service region plus the secondaries placement added" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      serving(["us-east", "eu-central"])
      {:ok, _primary} = PlacerRegions.put_primary(account, "us-east")
      {:ok, _secondary} = PlacerRegions.put_secondary(account, "eu-central")

      assert AccountPolicies.serving_regions(account) == ["us-east", "eu-central"]
    end

    test "excludes a region on its way out" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :enterprise)
      serving(["us-east", "eu-central"])
      {:ok, _primary} = PlacerRegions.put_primary(account, "us-east")
      {:ok, _secondary} = PlacerRegions.put_secondary(account, "eu-central")
      {:ok, _retiring} = PlacerRegions.mark_retiring(account, "eu-central")

      assert AccountPolicies.serving_regions(account) == ["us-east"]
    end

    test "is empty for an account that resolves to nothing" do
      account = organization_account()
      BillingFixtures.subscription_fixture(account_id: account.id, plan: :open_source)

      assert AccountPolicies.serving_regions(account) == []
    end
  end

  describe "the Air region" do
    test "is United States East for an account that states no storage region" do
      assert Environment.kura_air_region(:all) == "us-east"
      assert Environment.kura_air_region(:usa) == "us-east"
    end

    test "is unnamed for Europe until a deployment serves Air from there" do
      assert Environment.kura_air_region(:europe) == nil
    end

    test "is where an Air account resolves" do
      user = AccountsFixtures.user_fixture()
      account = Accounts.get_account_from_user(user)

      stub(Environment, :kura_air_region_ids, fn -> ["ca-east"] end)

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

    test "keeps a Europe-restricted Air account in Europe once a deployment serves it" do
      account = update_region!(organization_account(), :europe)

      stub(Environment, :kura_air_region_ids, fn -> ["us-east", "eu-central"] end)
      deploy_regions(["us-east", "eu-central"])

      assert AccountPolicies.resolve(account) == {:ok, %{plan: :air, service_region: "eu-central"}}
    end

    test "refuses a Europe-restricted Air account while no deployment serves Air in Europe" do
      # "Storage region" names module cache binaries, which is what a Kura
      # instance holds, so an account that chose Europe is refused rather than
      # served from the United States pool the rest of Air runs in.
      account = update_region!(organization_account(), :europe)

      deploy_regions(["us-east", "eu-central"])

      assert AccountPolicies.resolve(account) == {:error, :service_region_unavailable}
    end

    test "refuses a Europe-restricted Air account when the named region is not served here" do
      account = update_region!(organization_account(), :europe)

      stub(Environment, :kura_air_region, fn :europe -> "eu-central" end)
      deploy_regions(["us-east"])

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
