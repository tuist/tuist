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

  defp region, do: elem(Regions.fetch(@region), 1)

  defp installed(machines) do
    stub_region_nodes([{@region, List.duplicate(@node_allocatable_bytes, machines)}])
  end

  describe "resident_gib/2" do
    test "counts the instance's own claim, not the region's" do
      # us-east co-locates an account's two replicas on one box, so each claim
      # is reserved twice on the same disk.
      instance = %Server{storage_claim_size: "24Gi"}

      assert Capacity.resident_gib(region(), instance) == 24 * 2
      assert Capacity.resident_bytes(region(), instance) == 24 * 2 * @gib
    end

    test "reads an unpinned instance the way the manifest renders it" do
      # us-east declares no claim of its own, so an instance carrying none is
      # sized from its account's plan rather than read at the controller's
      # 200Gi fallback, which would overstate it by an order of magnitude.
      air = %Server{account: %Tuist.Accounts.Account{id: 1, name: "air", subscriptions: []}}

      assert Capacity.resident_gib(region(), air) == 8 * 2
    end

    test "reads every unit a claim may be persisted in" do
      # A claim is stored in whatever unit Kubernetes accepts and renders
      # verbatim onto the manifest. A parser that only understood Gi would read
      # the rest as unparseable and quietly substitute the region's claim, so an
      # instance reserving a terabyte would be counted at 50Gi.
      for {claim, gib} <- [{"1Ti", 1024}, {"40Gi", 40}, {"20480Mi", 20}, {"50G", 46}] do
        assert Capacity.resident_gib(region(), %Server{storage_claim_size: claim}) == gib * 2,
               "expected #{claim} to be read as #{gib} GiB per replica"
      end
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

  # What bounds a tenant's egress floor is everything reserved on its box, so
  # this is read per node and cluster-wide: a list narrowed to the pods this
  # control plane labels would miss whatever else the box carries and report the
  # box as roomier than it is.
  describe "egress_headroom/2" do
    setup do
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
      :ok
    end

    test "counts every pod on the box against it, not just the account's" do
      stub_egress_nodes(%{"box-1" => 500})

      stub(Client, :list_pods_on_node, fn "box-1" ->
        {:ok,
         [
           egress_pod("tuist", 25),
           egress_pod("tuist", 25),
           egress_pod("neighbour", 150),
           # No account label and no relation to Kura at all -- it still holds
           # 100 Mbps of the box, and the scheduler will not hand that out twice.
           unlabelled_egress_pod(100)
         ]}
      end)

      assert %{node: "box-1", allocatable_mbps: 500, available_mbps: 250, replicas: 2} =
               Capacity.egress_headroom(@region, "tuist")
    end

    # The account's own reservation is handed back replica by replica as the
    # rollout goes, so it is not spent from its own point of view.
    test "adds the account's own reservation back" do
      stub_egress_nodes(%{"box-1" => 500})
      stub(Client, :list_pods_on_node, fn "box-1" -> {:ok, [egress_pod("tuist", 200), egress_pod("tuist", 200)]} end)

      assert %{available_mbps: 500} = Capacity.egress_headroom(@region, "tuist")
    end

    # An unscheduled pod holds nothing on a node -- it is exactly the pod the
    # measurement exists to make room for.
    test "ignores a pod the scheduler has not placed" do
      stub_egress_nodes(%{"box-1" => 500})

      stub(Client, :list_pods_on_node, fn "box-1" ->
        {:ok, [egress_pod("tuist", 25), egress_pod("neighbour", 300, node: nil)]}
      end)

      assert %{available_mbps: 500} = Capacity.egress_headroom(@region, "tuist")
    end

    # A box can carry pods of the same account that belong to something else —
    # another region's instance, or a self-hosted deployment's own. They hold
    # whatever they hold against the box, but they are not replicas of the
    # instance being sized, and counting them divides the box by too many. On a
    # lab node three such pods turned a limit of 500 into one of 200.
    test "counts as replicas only the account's pods in this region" do
      stub_egress_nodes(%{"box-1" => 1000})

      stub(Client, :list_pods_on_node, fn "box-1" ->
        {:ok,
         [
           egress_pod("tuist", 200),
           egress_pod("tuist", 200),
           egress_pod("tuist", 0, region: "local"),
           egress_pod("tuist", 0, region: "local"),
           egress_pod("tuist", 0, region: "local")
         ]}
      end)

      assert %{available_mbps: 1000, replicas: 2} = Capacity.egress_headroom(@region, "tuist")
    end

    test "takes the box with least room for the account" do
      stub_egress_nodes(%{"box-1" => 500, "box-2" => 500})

      stub(Client, :list_pods_on_node, fn
        "box-1" -> {:ok, [egress_pod("tuist", 25, node: "box-1"), egress_pod("neighbour", 100, node: "box-1")]}
        "box-2" -> {:ok, [egress_pod("tuist", 25, node: "box-2"), egress_pod("neighbour", 300, node: "box-2")]}
      end)

      assert %{node: "box-2", available_mbps: 200} = Capacity.egress_headroom(@region, "tuist")
    end

    # A box only ever rebuilds the replicas that live on it -- each one's volume
    # pins it there -- so it is divided by those, not by the account's replicas
    # in the region. Dividing box-1 by 2 here would bound it twice as tightly as
    # the rollout it is describing.
    test "divides a box by the replicas that live on it" do
      stub_egress_nodes(%{"box-1" => 1000, "box-2" => 1000})

      stub(Client, :list_pods_on_node, fn
        "box-1" -> {:ok, [egress_pod("tuist", 100, node: "box-1"), egress_pod("neighbour", 400, node: "box-1")]}
        "box-2" -> {:ok, [egress_pod("tuist", 100, node: "box-2")]}
      end)

      assert %{node: "box-1", available_mbps: 600, replicas: 1} = Capacity.egress_headroom(@region, "tuist")
    end

    # A replica deleted and not yet recreated is in no pod list, and its volume
    # pins it to the box it left, so the box has to be sized for its return.
    # Counting only what is there would divide by too few and overstate the room.
    test "counts a replica the account is between" do
      stub_egress_nodes(%{"box-1" => 1000})
      stub(Client, :list_pods_on_node, fn "box-1" -> {:ok, [egress_pod("tuist", 100)]} end)

      assert %{replicas: 2} = Capacity.egress_headroom(@region, "tuist")
    end

    test "is unknown for an account with nothing on the region's boxes" do
      stub_egress_nodes(%{"box-1" => 500})
      stub(Client, :list_pods_on_node, fn "box-1" -> {:ok, [egress_pod("neighbour", 150)]} end)

      assert Capacity.egress_headroom(@region, "tuist") == nil
    end

    # Answering from the boxes that could be read would report a region as
    # roomier than it is, which is worse than reporting it as unknown: unknown
    # falls back to the advertised budget, and the form still refuses a floor it
    # cannot place.
    test "is unknown when a box cannot be read" do
      stub_egress_nodes(%{"box-1" => 500})
      stub(Client, :list_pods_on_node, fn "box-1" -> {:error, :unavailable} end)

      assert Capacity.egress_headroom(@region, "tuist") == nil
    end
  end

  defp stub_egress_nodes(allocatable_by_node) do
    stub(Client, :list_nodes, fn _selector ->
      {:ok,
       %{
         "items" =>
           Enum.map(allocatable_by_node, fn {name, mbps} ->
             %{
               "metadata" => %{"name" => name},
               "status" => %{
                 "conditions" => [%{"type" => "Ready", "status" => "True"}],
                 "allocatable" => %{"tuist.dev/egress-mbps" => Integer.to_string(mbps)}
               }
             }
           end)
       }}
    end)
  end

  defp egress_pod(handle, mbps, opts \\ []) do
    node = Keyword.get(opts, :node, "box-1")
    region = Keyword.get(opts, :region, @region)

    %{
      "metadata" => %{"labels" => %{"tuist.dev/account" => handle, "tuist.dev/region" => region}},
      "status" => %{"phase" => "Running"},
      "spec" =>
        Enum.into(if(node, do: %{"nodeName" => node}, else: %{}), %{
          "containers" => [%{"resources" => %{"requests" => %{"tuist.dev/egress-mbps" => Integer.to_string(mbps)}}}]
        })
    }
  end

  defp unlabelled_egress_pod(mbps) do
    %{
      "metadata" => %{"labels" => %{}},
      "status" => %{"phase" => "Running"},
      "spec" => %{
        "nodeName" => "box-1",
        "containers" => [%{"resources" => %{"requests" => %{"tuist.dev/egress-mbps" => Integer.to_string(mbps)}}}]
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
