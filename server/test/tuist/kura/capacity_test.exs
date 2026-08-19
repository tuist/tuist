defmodule Tuist.Kura.CapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Capacity
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.BillingFixtures

  setup :set_mimic_from_context

  @region "us-east"
  @gib 1024 * 1024 * 1024
  # Roughly what one of the region's real boxes reports allocatable, so the
  # arithmetic under test is the arithmetic production does.
  @node_allocatable_bytes 847_551_469_804
  # `installed_gib/1` keeps 85% of allocatable clear of kubelet's eviction line.
  @usable_gib trunc(@node_allocatable_bytes * 0.85 / @gib)
  # us-east runs two co-located replicas, so an instance holds two quotas.
  @air_resident_gib 24 * 2

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
    stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, machines)}])
  end

  # Fills the region to just under its usable capacity, leaving no room for
  # one more Air instance.
  defp fill_region do
    for _ <- 1..div(@usable_gib, @air_resident_gib), do: instance(account())
  end

  describe "warm_quota_gib/2" do
    test "sizes Air from its own quota and paid plans from the region's storage claim" do
      {:ok, region} = Regions.fetch(@region)

      assert Capacity.warm_quota_gib(:air, region) == 24
      assert Capacity.warm_quota_gib(:pro, region) == 50
      assert Capacity.warm_quota_gib(:enterprise, region) == 50
    end

    test "counts every co-located replica against the region's disk" do
      {:ok, region} = Regions.fetch(@region)

      assert Capacity.resident_gib(:air, region) == 24 * 2
      assert Capacity.resident_gib(:pro, region) == 50 * 2
      assert Capacity.resident_bytes(:air, region) == 24 * 2 * @gib
    end
  end

  describe "forecast_gib/1" do
    test "counts live instances and ignores archived and destroyed ones" do
      instance(account())
      instance(account(:pro))
      instance(account(), :archived)
      instance(account(), :destroyed)

      assert Capacity.forecast_gib(@region) == (24 + 50) * 2
    end

    test "counts a draining instance, which still holds its directory" do
      instance(account(), :drain_pending)

      assert Capacity.forecast_gib(@region) == 24 * 2
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
      fill_region()

      assert {:error, {:no_safe_slot, details}} = Capacity.admit(@region, :air)
      assert details.region == @region
      assert details.installed_gib == @usable_gib
      assert details.forecast_gib > @usable_gib
    end

    test "admits when the region's capacity cannot be established" do
      stub_region_nodes([])

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
      fill_region()
      instance(account())

      assert Capacity.under_pressure?(@region)
    end

    test "is false when capacity is unknown, so pressure archival never runs uninformed" do
      stub_region_nodes([])

      for _ <- 1..100, do: instance(account())

      refute Capacity.under_pressure?(@region)
    end
  end

  describe "environment configuration" do
    test "the lifecycle windows default to the spec's values and are overridable" do
      # Configurable so the archival half can be exercised outside production
      # rather than first running for real against customer instances.
      assert Environment.kura_inactive_days() == 90
      assert Environment.kura_pressure_inactive_days() == 60
      assert Environment.kura_demand_tracking_grace_days() == 7
    end
  end

  describe "occupancy/1" do
    test "reports the forecast against what is installed" do
      installed(2)
      instance(account())
      instance(account(:pro))

      occupancy = Capacity.occupancy(@region)

      assert occupancy.instances == 2
      assert occupancy.forecast_gib == (24 + 50) * 2
      assert occupancy.installed_gib == trunc(2 * @node_allocatable_bytes * 0.85 / @gib)
      assert occupancy.ratio == occupancy.forecast_gib / occupancy.installed_gib
    end

    test "leaves installed capacity and ratio unknown when the machine count is not configured" do
      stub_region_nodes([])
      instance(account())

      occupancy = Capacity.occupancy(@region)

      assert occupancy.installed_gib == nil
      assert occupancy.ratio == nil
    end
  end

  # `installed_gib/1` sums the allocatable ephemeral storage of a region's
  # Ready nodes, so sizing a region in a test means answering the node list.
  defp stub_region_nodes(nodes_by_region) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

    stub(Client, :list_nodes, fn selector ->
      allocatable =
        Enum.find_value(nodes_by_region, [], fn {region_id, allocatable} ->
          {:ok, region} = Regions.fetch(region_id)
          if selector == Regions.node_label_selector(region), do: allocatable
        end)

      {:ok, %{"items" => Enum.map(allocatable, &ready_node/1)}}
    end)
  end

  defp ready_node(allocatable_bytes) do
    %{
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => "True"}],
        "allocatable" => %{"ephemeral-storage" => Integer.to_string(allocatable_bytes)}
      }
    }
  end
end
