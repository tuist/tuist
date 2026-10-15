defmodule Tuist.Kura.DemandTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Demand.Kicks
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  # Resolution refuses a region the deployment does not serve, so these tests
  # state the deployment they assume rather than inheriting the test env's
  # local-controller-only catalog.
  setup do
    stub(Environment, :dev?, fn -> false end)
    stub(Environment, :test?, fn -> false end)
    stub(Environment, :kura_available_region_ids, fn -> ["us-east", "us-west", "eu-west"] end)
    :ok
  end

  # Tests run with the buffer bypassed by default so async tests cannot flush
  # each other's demand (see `config/test.exs`). These tests are about the
  # buffer itself, so they turn it back on. Safe because the case is
  # synchronous: ExUnit runs sync cases only once every async one has
  # finished.
  setup do
    stub(Environment, :kura_demand_write_through_repo?, fn -> false end)
    Demand.flush()
    :ok
  end

  defp air_account do
    user = AccountsFixtures.user_fixture()
    Accounts.get_account_from_user(user)
  end

  defp paid_account(plan, region) do
    account = air_account()
    BillingFixtures.subscription_fixture(account_id: account.id, plan: plan)
    {:ok, account} = Accounts.update_account(account, %{region: region})
    account
  end

  describe "record/1" do
    test "does not write to the database until flushed" do
      account = air_account()

      assert :ok = Demand.record(account.id)
      assert Demand.get(account.id, "us-east") == nil

      assert {:ok, 1} = Demand.flush()
      assert %AccountRegionLifecycle{} = Demand.get(account.id, "us-east")
    end

    test "coalesces repeated demand from one account into a single row" do
      account = air_account()

      for _ <- 1..50, do: Demand.record(account.id)

      assert {:ok, 1} = Demand.flush()

      assert Repo.aggregate(
               from(l in AccountRegionLifecycle, where: l.account_id == ^account.id),
               :count
             ) == 1
    end

    test "resolves the account's service region rather than assuming one" do
      europe = paid_account(:pro, :europe)
      usa = paid_account(:pro, :usa)

      Demand.record(europe.id)
      Demand.record(usa.id)

      assert {:ok, 2} = Demand.flush()

      assert %AccountRegionLifecycle{} = Demand.get(europe.id, "eu-west")
      assert %AccountRegionLifecycle{} = Demand.get(usa.id, "us-east")
    end

    test "records a paid account allowing every region against the default" do
      account = paid_account(:pro, :all)

      Demand.record(account.id)

      assert {:ok, 1} = Demand.flush()
      assert %AccountRegionLifecycle{} = Demand.get(account.id, "us-east")
    end

    test "skips accounts with no resolvable service region" do
      # A plan Kura does not serve resolves to no region, so there is no
      # account-region instance for its demand to keep warm.
      account = paid_account(:open_source, :all)

      Demand.record(account.id)

      assert {:ok, 0} = Demand.flush()
      assert Repo.aggregate(from(l in AccountRegionLifecycle, where: l.account_id == ^account.id), :count) == 0
    end

    test "never regresses a stored timestamp" do
      account = air_account()
      later = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, 1} = Demand.upsert(account.id, "us-east", later)

      Demand.record(account.id)
      {:ok, 1} = Demand.flush()

      assert DateTime.compare(Demand.get(account.id, "us-east").last_cache_demand_at, DateTime.truncate(later, :second)) ==
               :eq
    end

    test "is a no-op for a non-integer account id" do
      assert :ok = Demand.record(nil)
      assert {:ok, 0} = Demand.flush()
    end

    test "advances the traffic clock only for a request that moved bytes" do
      resolving = air_account()
      transferring = air_account()

      Demand.record(resolving.id)
      Demand.record(transferring.id, nil, traffic: true)
      assert {:ok, 2} = Demand.flush()

      assert %AccountRegionLifecycle{last_cache_demand_at: %DateTime{}, last_cache_traffic_at: nil} =
               Demand.get(resolving.id, "us-east")

      assert %AccountRegionLifecycle{last_cache_demand_at: demand_at, last_cache_traffic_at: traffic_at} =
               Demand.get(transferring.id, "us-east")

      assert traffic_at == demand_at
    end

    test "keeps the traffic clock when later demand moves no bytes" do
      account = air_account()

      Demand.record(account.id, nil, traffic: true)
      {:ok, 1} = Demand.flush()
      traffic_at = Demand.get(account.id, "us-east").last_cache_traffic_at

      Demand.record(account.id)
      {:ok, 1} = Demand.flush()

      assert Demand.get(account.id, "us-east").last_cache_traffic_at == traffic_at
    end

    test "persists a traffic entry whose demand entry an earlier flush already took" do
      account = air_account()
      now = System.system_time(:second)
      :ets.insert(Demand, {{:traffic, account.id}, now})

      assert {:ok, 1} = Demand.flush()

      assert %AccountRegionLifecycle{last_cache_demand_at: demand_at, last_cache_traffic_at: traffic_at} =
               Demand.get(account.id, "us-east")

      assert demand_at == DateTime.from_unix!(now)
      assert traffic_at == DateTime.from_unix!(now)
    end
  end

  describe "idle_hold?/1" do
    defp archived_as(account, reason, archived_days_ago, traffic_days_ago) do
      at = fn days -> days && DateTime.truncate(DateTime.add(DateTime.utc_now(), -days * 86_400, :second), :second) end
      {:ok, 1} = Demand.upsert(account.id, "us-east", at.(archived_days_ago + 1))

      account.id
      |> Demand.get("us-east")
      |> Ecto.Changeset.change(%{
        drain_reason: reason,
        archived_at: at.(archived_days_ago),
        last_cache_traffic_at: at.(traffic_days_ago)
      })
      |> Repo.update!()
    end

    test "holds an idle archival with no traffic since, inside the hold" do
      account = air_account()
      archived_as(account, :idle, 1, nil)

      assert Demand.idle_hold?(account)
    end

    test "releases once the hold has run out" do
      account = air_account()
      archived_as(account, :idle, Demand.idle_hold_days() + 1, nil)

      refute Demand.idle_hold?(account)
    end

    test "releases on traffic after the archival" do
      account = air_account()
      archived_as(account, :idle, 2, 1)

      refute Demand.idle_hold?(account)
    end

    test "does not hold an ordinary inactive archival" do
      account = air_account()
      archived_as(account, :inactive, 1, nil)

      refute Demand.idle_hold?(account)
    end

    test "skips an account deleted after its region was resolved" do
      deleted = air_account()
      live = air_account()

      stub(AccountPolicies, :serving_regions_all, fn accounts ->
        resolutions = Mimic.call_original(AccountPolicies, :serving_regions_all, [accounts])
        Repo.delete_all(from(a in Account, where: a.id == ^deleted.id))
        resolutions
      end)

      Demand.record(deleted.id)
      Demand.record(live.id)

      assert {:ok, 1} = Demand.flush()
      assert Demand.get(deleted.id, "us-east") == nil
      assert %AccountRegionLifecycle{} = Demand.get(live.id, "us-east")
    end
  end

  describe "upsert_many/1" do
    test "inserts rows in account and service region order" do
      first = air_account()
      second = air_account()
      now = DateTime.utc_now()

      rows =
        Enum.map(
          [{second.id, "us-west"}, {second.id, "eu-west"}, {first.id, "us-west"}, {first.id, "eu-west"}],
          fn {account_id, service_region} ->
            %{account_id: account_id, service_region: service_region, last_cache_demand_at: now}
          end
        )

      test_pid = self()

      stub(Repo, :insert_all, fn schema, rows, opts ->
        send(test_pid, {:insert_all, schema, rows})
        Mimic.call_original(Repo, :insert_all, [schema, rows, opts])
      end)

      assert {:ok, 4} = Demand.upsert_many(rows)
      assert_received {:insert_all, AccountRegionLifecycle, inserted_rows}

      assert Enum.map(inserted_rows, &{&1.account_id, &1.service_region}) == [
               {first.id, "eu-west"},
               {first.id, "us-west"},
               {second.id, "eu-west"},
               {second.id, "us-west"}
             ]

      for {account_id, service_region} <- Enum.map(rows, &{&1.account_id, &1.service_region}) do
        assert %AccountRegionLifecycle{} = Demand.get(account_id, service_region)
      end
    end

    test "writes a batch in one statement and keeps the latest timestamp per row" do
      first = air_account()
      second = paid_account(:pro, :europe)
      earlier = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, 2} =
        Demand.upsert_many([
          %{account_id: first.id, service_region: "us-east", last_cache_demand_at: earlier},
          %{account_id: second.id, service_region: "eu-west", last_cache_demand_at: earlier}
        ])

      later = DateTime.utc_now()

      {:ok, 1} =
        Demand.upsert_many([
          %{account_id: first.id, service_region: "us-east", last_cache_demand_at: later}
        ])

      assert DateTime.compare(
               Demand.get(first.id, "us-east").last_cache_demand_at,
               DateTime.truncate(later, :second)
             ) == :eq

      assert DateTime.compare(
               Demand.get(second.id, "eu-west").last_cache_demand_at,
               DateTime.truncate(earlier, :second)
             ) == :eq
    end

    test "skips rows for accounts that no longer exist" do
      live = air_account()
      deleted = air_account()
      Repo.delete_all(from(a in Account, where: a.id == ^deleted.id))

      assert {:ok, 1} =
               Demand.upsert_many([
                 %{account_id: live.id, service_region: "us-east", last_cache_demand_at: DateTime.utc_now()},
                 %{account_id: deleted.id, service_region: "us-east", last_cache_demand_at: DateTime.utc_now()}
               ])

      assert %AccountRegionLifecycle{} = Demand.get(live.id, "us-east")
    end

    test "is a no-op on an empty batch" do
      assert {:ok, 0} = Demand.upsert_many([])
    end
  end

  describe "lifecycle_managed?/1" do
    test "is false before any Kura cache demand and true after" do
      account = air_account()

      refute Demand.lifecycle_managed?(account)

      Demand.record(account.id)
      Demand.flush()

      assert Demand.lifecycle_managed?(account)
    end
  end

  describe "set_keep_warm/3" do
    test "sets and clears the account-region exception" do
      account = air_account()
      Demand.record(account.id)
      Demand.flush()

      assert {:ok, lifecycle} = Demand.set_keep_warm(account.id, "us-east", true)
      assert lifecycle.keep_warm

      assert {:ok, lifecycle} = Demand.set_keep_warm(account.id, "us-east", false)
      refute lifecycle.keep_warm
    end

    test "reports a missing account-region" do
      account = air_account()

      assert {:error, :not_found} = Demand.set_keep_warm(account.id, "us-east", true)
    end
  end

  describe "claim_provision_kick/1" do
    test "lets the first resolution through and holds the rest of the window" do
      # Every client of an account with nothing serving asks, and asks again on
      # the provisioning answer's short max age. Acting on each would cost a
      # write-through and a unique job insert per request, to schedule work the
      # job's own unique window deduplicates anyway.
      account_id = System.unique_integer([:positive])

      assert Demand.claim_provision_kick(account_id)
      refute Demand.claim_provision_kick(account_id)
      refute Demand.claim_provision_kick(account_id)
    end

    test "keeps separate windows per account" do
      assert Demand.claim_provision_kick(System.unique_integer([:positive]))
      assert Demand.claim_provision_kick(System.unique_integer([:positive]))
    end

    test "backs a streak off to the tick's cadence once it outlives a provisioning attempt" do
      # An account still asking a quarter of an hour later is one its region is
      # refusing for capacity, or one whose provision is wedged. Neither is
      # something another kick places, and both are owned by the reconciler
      # tick and the stalled-instance alert.
      account_id = System.unique_integer([:positive])
      now = System.monotonic_time(:millisecond)
      started_ms = now - to_timeout(minute: 20)

      :ets.insert(Kicks, {account_id, now - 1, started_ms})

      assert Demand.claim_provision_kick(account_id)

      assert [{^account_id, next_allowed_ms, ^started_ms}] =
               :ets.lookup(Kicks, account_id)

      assert next_allowed_ms - now >= to_timeout(minute: 1) - 5
    end

    test "starts a new streak for an account that stopped asking" do
      account_id = System.unique_integer([:positive])
      now = System.monotonic_time(:millisecond)
      stale = now - to_timeout(minute: 30)

      :ets.insert(Kicks, {account_id, stale, stale - to_timeout(minute: 20)})

      assert Demand.claim_provision_kick(account_id)

      assert [{^account_id, next_allowed_ms, streak_started_ms}] =
               :ets.lookup(Kicks, account_id)

      assert streak_started_ms >= now
      assert next_allowed_ms - streak_started_ms == to_timeout(second: 5)
    end
  end
end
