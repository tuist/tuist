defmodule Tuist.Kura.DemandTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Kura.Demand
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

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

      assert %AccountRegionLifecycle{} = Demand.get(europe.id, "eu-central")
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
  end

  describe "upsert_many/1" do
    test "writes a batch in one statement and keeps the latest timestamp per row" do
      first = air_account()
      second = paid_account(:pro, :europe)
      earlier = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, 2} =
        Demand.upsert_many([
          %{account_id: first.id, service_region: "us-east", last_cache_demand_at: earlier},
          %{account_id: second.id, service_region: "eu-central", last_cache_demand_at: earlier}
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
               Demand.get(second.id, "eu-central").last_cache_demand_at,
               DateTime.truncate(earlier, :second)
             ) == :eq
    end

    test "starts the transfer clock on a new row, so the archival sweep can eventually read it" do
      account = air_account()

      {:ok, 1} =
        Demand.upsert_many([
          %{account_id: account.id, service_region: "us-east", last_cache_demand_at: DateTime.utc_now()}
        ])

      assert Demand.get(account.id, "us-east").transfer_tracking_started_at
    end

    test "does not restart the transfer clock on an existing row" do
      account = air_account()
      {:ok, 1} = Demand.upsert(account.id, "us-east", DateTime.add(DateTime.utc_now(), -3600, :second))
      started_at = Demand.get(account.id, "us-east").transfer_tracking_started_at

      {:ok, 1} = Demand.upsert(account.id, "us-east", DateTime.utc_now())

      assert Demand.get(account.id, "us-east").transfer_tracking_started_at == started_at
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
end
