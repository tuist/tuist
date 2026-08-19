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
  @allocatable_gib trunc(@node_allocatable_bytes / @gib)
  # us-east declares a 50Gi claim and two co-located replicas, so each
  # instance reserves two claims on the one box.
  @resident_gib 50 * 2

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

  describe "resident_gib/1" do
    test "counts every co-located replica of the region's claim" do
      {:ok, region} = Regions.fetch(@region)

      assert Capacity.resident_gib(region) == 50 * 2
      assert Capacity.resident_bytes(region) == 50 * 2 * @gib
    end
  end

  describe "allocatable_gib/1" do
    test "sums the region's Ready nodes" do
      installed(2)

      assert Capacity.allocatable_gib(@region) == trunc(2 * @node_allocatable_bytes / @gib)
    end

    test "ignores a node that is not Ready, whose disk cannot be scheduled onto" do
      stub_region_nodes([{@region, [@node_allocatable_bytes]}], ready?: false)

      assert Capacity.allocatable_gib(@region) == nil
    end

    test "is unknown when the cluster cannot be read" do
      stub_region_nodes([])

      assert Capacity.allocatable_gib(@region) == nil
    end
  end

  describe "reserved_gib/1" do
    test "sums what the region's pods request, across containers" do
      stub_region_pods([reserved_pod(50), reserved_pod(50), reserved_pod(50)])

      assert Capacity.reserved_gib(@region) == 150
    end

    test "ignores a pod that has finished, which holds nothing" do
      stub_region_pods([reserved_pod(50), Map.put(reserved_pod(50), "status", %{"phase" => "Failed"})])

      assert Capacity.reserved_gib(@region) == 50
    end

    test "counts a pod that requests nothing as nothing rather than failing" do
      stub_region_pods([reserved_pod(50), %{"spec" => %{"containers" => [%{}]}}])

      assert Capacity.reserved_gib(@region) == 50
    end

    test "is unknown when the cluster cannot be read" do
      stub(Client, :list_pods, fn _namespace, _selector -> {:error, :unavailable} end)
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

      assert Capacity.reserved_gib(@region) == nil
    end
  end

  describe "under_pressure?/1" do
    test "is false while the region is under its pressure line" do
      installed(1)
      stub_region_pods([reserved_pod(50)])

      refute Capacity.under_pressure?(@region)
    end

    test "is true once the region has reserved past its pressure line" do
      installed(1)
      stub_region_pods(List.duplicate(reserved_pod(50), div(@allocatable_gib, 50)))

      assert Capacity.under_pressure?(@region)
    end

    test "is false when capacity is unknown, so pressure archival never runs uninformed" do
      stub_region_nodes([])
      stub_region_pods(List.duplicate(reserved_pod(50), 100))

      refute Capacity.under_pressure?(@region)
    end

    test "is false when the reservation cannot be read" do
      installed(1)
      stub(Client, :list_pods, fn _namespace, _selector -> {:error, :unavailable} end)

      refute Capacity.under_pressure?(@region)
    end
  end

  describe "pressure_line_gib/1" do
    test "leaves headroom below allocatable, so archival makes room before placement fails" do
      installed(1)

      assert Capacity.pressure_line_gib(@region) == trunc(@allocatable_gib * 0.85)
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

  # `installed_gib/1` sums the allocatable ephemeral storage of a region's
  # Ready nodes, so sizing a region in a test means answering the node list.
  defp stub_region_nodes(nodes_by_region, opts \\ []) do
    ready? = Keyword.get(opts, :ready?, true)
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

    stub(Client, :list_nodes, fn selector ->
      allocatable =
        Enum.find_value(nodes_by_region, [], fn {region_id, allocatable} ->
          {:ok, region} = Regions.fetch(region_id)
          if selector == Regions.node_label_selector(region), do: allocatable
        end)

      {:ok, %{"items" => Enum.map(allocatable, &node(&1, ready?))}}
    end)
  end

  defp node(allocatable_bytes, ready?) do
    %{
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => ready? |> to_string() |> String.capitalize()}],
        "allocatable" => %{"ephemeral-storage" => Integer.to_string(allocatable_bytes)}
      }
    }
  end

  # `reserved_gib/1` reads the pods' own ephemeral-storage requests, so
  # reserving disk in a test means answering the pod list.
  defp stub_region_pods(pods) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Client, :list_pods, fn _namespace, _selector -> {:ok, pods} end)
  end

  defp reserved_pod(gib) do
    %{
      "status" => %{"phase" => "Running"},
      "spec" => %{
        "containers" => [%{"resources" => %{"requests" => %{"ephemeral-storage" => "#{gib}Gi"}}}]
      }
    }
  end

  describe "occupancy/1" do
    test "reports what the region has reserved against what it has" do
      installed(2)
      stub_region_pods([reserved_pod(50), reserved_pod(50)])
      instance(account())
      instance(account(:pro))

      occupancy = Capacity.occupancy(@region)

      assert occupancy.instances == 2
      assert occupancy.reserved_gib == 100
      assert occupancy.allocatable_gib == trunc(2 * @node_allocatable_bytes / @gib)
      assert occupancy.ratio == occupancy.reserved_gib / occupancy.allocatable_gib
    end

    test "leaves the reading unknown when the cluster cannot be read" do
      stub_region_nodes([])
      stub(Client, :list_pods, fn _namespace, _selector -> {:error, :unavailable} end)
      instance(account())

      occupancy = Capacity.occupancy(@region)

      assert occupancy.instances == 1
      assert occupancy.reserved_gib == nil
      assert occupancy.allocatable_gib == nil
      assert occupancy.ratio == nil
    end
  end
end
