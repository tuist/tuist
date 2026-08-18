defmodule Tuist.Kura.CapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @region "us-east"
  # One machine's usable filesystem, from the regional capacity model.
  @usable_gib 1105

  defp account(plan \\ nil) do
    user = AccountsFixtures.user_fixture()
    account = Accounts.get_account_from_user(user)
    if plan, do: BillingFixtures.subscription_fixture(account_id: account.id, plan: plan)
    account
  end

  defp instance(account, status \\ :active) do
    Repo.insert!(%Server{
      account_id: account.id,
      region: @region,
      status: status,
      provisioner_node_ref: "kura-#{account.id}-us-east"
    })
  end

  defp installed(machines) do
    stub(Environment, :kura_region_machines, fn @region -> machines end)
  end

  describe "warm_quota_gib/2" do
    test "sizes Air from its own quota and paid plans from the region's storage claim" do
      {:ok, region} = Regions.fetch(@region)

      assert Capacity.warm_quota_gib(:air, region) == 24
      assert Capacity.warm_quota_gib(:pro, region) == 50
      assert Capacity.warm_quota_gib(:enterprise, region) == 50
    end
  end

  describe "forecast_gib/1" do
    test "counts live instances and ignores archived and destroyed ones" do
      instance(account())
      instance(account(:pro))
      instance(account(), :archived)
      instance(account(), :destroyed)

      assert Capacity.forecast_gib(@region) == 24 + 50
    end

    test "counts a draining instance, which still holds its directory" do
      instance(account(), :drain_pending)

      assert Capacity.forecast_gib(@region) == 24
    end
  end

  describe "admit/2" do
    test "admits while the forecast still fits" do
      installed(1)
      instance(account())

      assert :ok = Capacity.admit(@region, :air)
    end

    test "refuses rather than overcommitting a machine" do
      installed(1)

      for _ <- 1..46, do: instance(account())

      assert {:error, {:no_safe_slot, details}} = Capacity.admit(@region, :air)
      assert details.region == @region
      assert details.installed_gib == @usable_gib
      assert details.forecast_gib > @usable_gib
    end

    test "admits when the region's machine count is not configured" do
      stub(Environment, :kura_region_machines, fn _ -> nil end)

      for _ <- 1..100, do: instance(account())

      assert :ok = Capacity.admit(@region, :air)
    end

    test "reports an unknown region rather than admitting into it" do
      assert {:error, :not_found} = Capacity.admit("moon", :air)
    end
  end

  describe "under_pressure?/1" do
    test "is false while the forecast fits, so the 90-day target is preserved" do
      installed(1)
      instance(account())

      refute Capacity.under_pressure?(@region)
    end

    test "is true once the forecast exceeds what is installed" do
      installed(1)

      for _ <- 1..47, do: instance(account())

      assert Capacity.under_pressure?(@region)
    end

    test "is false when capacity is unknown, so pressure archival never runs uninformed" do
      stub(Environment, :kura_region_machines, fn _ -> nil end)

      for _ <- 1..100, do: instance(account())

      refute Capacity.under_pressure?(@region)
    end
  end

  describe "environment configuration" do
    test "an unreadable machine count raises rather than reading as unknown capacity" do
      # `nil` disables admission and pressure archival, so a typo must not be
      # indistinguishable from deliberately omitting the region.
      for value <- ["O", "4x", "", "0", "-2"] do
        assert_raise ArgumentError, ~r/invalid machine count for us-east/, fn ->
          Environment.kura_region_machines("us-east", "us-east=#{value}")
        end
      end
    end

    test "a region that is simply absent reads as unknown" do
      assert Environment.kura_region_machines("us-east", "eu-central=2") == nil
      assert Environment.kura_region_machines("eu-central", "eu-central=2") == 2
      assert Environment.kura_region_machines("us-east", "") == nil
    end

    test "reads a well-formed list" do
      assert Environment.kura_region_machines("us-east", "us-east=4, eu-central=2") == 4
    end
  end

  describe "occupancy/1" do
    test "reports the forecast against what is installed" do
      installed(2)
      instance(account())
      instance(account(:pro))

      occupancy = Capacity.occupancy(@region)

      assert occupancy.instances == 2
      assert occupancy.forecast_gib == 74
      assert occupancy.installed_gib == 2 * @usable_gib
      assert occupancy.ratio == 74 / (2 * @usable_gib)
    end

    test "leaves installed capacity and ratio unknown when the machine count is not configured" do
      stub(Environment, :kura_region_machines, fn _ -> nil end)
      instance(account())

      occupancy = Capacity.occupancy(@region)

      assert occupancy.installed_gib == nil
      assert occupancy.ratio == nil
    end
  end
end
