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

  # What bounds a tenant's egress floor is what its own box has left, so this
  # reads that box: the account's pods say which one it is, and everything on it
  # counts against it, whoever owns it.
  describe "egress_headroom/2" do
    setup do
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
      :ok
    end

    test "asks only for the account's own pods in this region" do
      stub_box("box-1", 500, [egress_pod("tuist", 25), egress_pod("tuist", 25)])

      stub(Client, :list_pods, fn "kura", selector, _opts ->
        assert selector =~ "tuist.dev/region=#{@region}"
        assert selector =~ "tuist.dev/account=tuist"
        assert selector =~ "app.kubernetes.io/managed-by=kura-controller"
        {:ok, [egress_pod("tuist", 25), egress_pod("tuist", 25)]}
      end)

      assert %{node: "box-1"} = Capacity.egress_headroom(@region, "tuist")
    end

    test "counts every pod on the box against it, not just the account's" do
      stub_box("box-1", 500, [
        egress_pod("tuist", 25),
        egress_pod("tuist", 25),
        egress_pod("neighbour", 150),
        # No account label and no relation to Kura at all -- it still holds
        # 100 Mbps of the box, and the scheduler will not hand that out twice.
        unlabelled_egress_pod(100)
      ])

      stub_account_pods([egress_pod("tuist", 25), egress_pod("tuist", 25)])

      assert %{node: "box-1", allocatable_mbps: 500, available_mbps: 250, replicas: 2} =
               Capacity.egress_headroom(@region, "tuist")
    end

    # The account's own reservation is handed back replica by replica as the
    # rollout goes, so it is not spent from its own point of view.
    test "adds the account's own reservation back" do
      pods = [egress_pod("tuist", 200), egress_pod("tuist", 200)]
      stub_box("box-1", 500, pods)
      stub_account_pods(pods)

      assert %{available_mbps: 500} = Capacity.egress_headroom(@region, "tuist")
    end

    # An unscheduled pod holds nothing on a node -- it is exactly the pod the
    # measurement exists to make room for.
    test "ignores a pod the scheduler has not placed" do
      stub_box("box-1", 500, [egress_pod("tuist", 25)])
      stub_account_pods([egress_pod("tuist", 25), egress_pod("tuist", 300, node: nil)])

      assert %{available_mbps: 500, replicas: 2} = Capacity.egress_headroom(@region, "tuist")
    end

    # A replica deleted and not yet recreated is in no pod list, and its volume
    # pins it to the box it left, so the box has to be sized for its return.
    test "counts a replica the account is between" do
      stub_box("box-1", 1000, [egress_pod("tuist", 100)])
      stub_account_pods([egress_pod("tuist", 100)])

      assert %{replicas: 2} = Capacity.egress_headroom(@region, "tuist")
    end

    test "is unknown for an account with nothing on the region's boxes" do
      stub_box("box-1", 500, [egress_pod("neighbour", 150)])
      stub_account_pods([])

      assert Capacity.egress_headroom(@region, "tuist") == nil
    end

    # Reporting the box as roomier than it is would be worse than reporting it
    # as unknown: unknown falls back to the advertised budget, and the form still
    # refuses a floor it cannot place.
    test "is unknown when the box cannot be read" do
      stub(Client, :get_node, fn _node, _opts -> {:error, :unavailable} end)
      stub(Client, :list_pods_on_node, fn _node, _opts -> {:error, :unavailable} end)
      stub_account_pods([egress_pod("tuist", 25)])

      assert Capacity.egress_headroom(@region, "tuist") == nil
    end
  end

  defp stub_account_pods(pods) do
    stub(Client, :list_pods, fn "kura", _selector, _opts -> {:ok, pods} end)
  end

  defp stub_box(node, allocatable_mbps, pods) do
    stub(Client, :get_node, fn ^node, _opts ->
      {:ok,
       %{
         "metadata" => %{"name" => node},
         "status" => %{"allocatable" => %{"tuist.dev/egress-mbps" => Integer.to_string(allocatable_mbps)}}
       }}
    end)

    stub(Client, :list_pods_on_node, fn ^node, _opts -> {:ok, pods} end)
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
