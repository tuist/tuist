defmodule Tuist.Kura.CapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
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
      air = %Server{account: %Account{id: 1, name: "air", subscriptions: []}}

      assert Capacity.resident_gib(region(), air) == 8 * 2
    end

    test "runner fallback stays at the legacy reservation when account and pin are absent" do
      runner = Regions.get("scw-fr-par-runners")
      assert Capacity.resident_gib(runner, %Server{}) == 50 * 2
      assert Capacity.resident_gib(runner, %Server{storage_claim_size: "invalid"}) == 50 * 2
      assert Capacity.resident_gib(runner, %Server{storage_claim_size: "24Gi"}) == 24 * 2
      air = %Server{account: %Account{id: 1, name: "air", subscriptions: []}}
      assert Capacity.resident_gib(runner, air) == 8 * 2
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

      assert %{node: "box-1", allocatable_mbps: 500, available_mbps: 250, replicas: 2, boxes: 1} =
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

    # A terminal replica -- evicted off a disk-pressured box, and lingering in
    # the API until something deletes it -- is excluded from the box's reserved
    # total by the field selector, so counting it as the account's own would add
    # back a reservation nobody holds and report more available than the box has.
    test "ignores a terminal pod of the account's own" do
      stub_box("box-1", 1000, [egress_pod("tuist", 100), egress_pod("neighbour", 200)])

      stub_account_pods([
        egress_pod("tuist", 100),
        egress_pod("tuist", 400, phase: "Failed")
      ])

      assert %{available_mbps: 800, replicas: 2} = Capacity.egress_headroom(@region, "tuist")
    end

    # An unscheduled pod holds nothing on a node -- it is exactly the pod the
    # measurement exists to make room for.
    test "ignores a pod the scheduler has not placed" do
      stub_box("box-1", 500, [egress_pod("tuist", 25)])
      stub_account_pods([egress_pod("tuist", 25), egress_pod("tuist", 300, node: nil)])

      assert %{available_mbps: 500, replicas: 2} = Capacity.egress_headroom(@region, "tuist")
    end

    # podAffinity is preferred, not required, so a box that cannot fit the second
    # replica leaves the account straddling two — and each replica's volume pins
    # it where it landed. Reporting the roomy box would admit a floor the other
    # one can never place.
    test "takes the box that can hold the smallest floor" do
      stub_boxes(%{
        "roomy" => {1000, [egress_pod("tuist", 100, node: "roomy")]},
        "constrained" =>
          {1000, [egress_pod("tuist", 100, node: "constrained"), egress_pod("neighbour", 900, node: "constrained")]}
      })

      stub_account_pods([
        egress_pod("tuist", 100, node: "roomy"),
        egress_pod("tuist", 100, node: "constrained")
      ])

      assert %{node: "constrained", available_mbps: 100, replicas: 1, boxes: 2} =
               Capacity.egress_headroom(@region, "tuist")
    end

    # Each box rebuilds only its own replicas, so a split box is divided by one,
    # not by the region's two.
    test "divides each box by the replicas that live on it" do
      stub_boxes(%{
        "box-1" => {1000, [egress_pod("tuist", 100, node: "box-1"), egress_pod("neighbour", 400, node: "box-1")]},
        "box-2" => {1000, [egress_pod("tuist", 100, node: "box-2")]}
      })

      stub_account_pods([
        egress_pod("tuist", 100, node: "box-1"),
        egress_pod("tuist", 100, node: "box-2")
      ])

      assert %{node: "box-1", available_mbps: 600, replicas: 1} = Capacity.egress_headroom(@region, "tuist")
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

  defp stub_box(node, allocatable_mbps, pods), do: stub_boxes(%{node => {allocatable_mbps, pods}})

  defp stub_boxes(boxes) do
    stub(Client, :get_node, fn node, _opts ->
      case Map.fetch(boxes, node) do
        {:ok, {allocatable_mbps, _pods}} ->
          {:ok,
           %{
             "metadata" => %{"name" => node},
             "status" => %{"allocatable" => %{"tuist.dev/egress-mbps" => Integer.to_string(allocatable_mbps)}}
           }}

        :error ->
          {:error, :not_found}
      end
    end)

    stub(Client, :list_pods_on_node, fn node, _opts ->
      case Map.fetch(boxes, node) do
        {:ok, {_allocatable_mbps, pods}} -> {:ok, pods}
        :error -> {:error, :not_found}
      end
    end)
  end

  defp egress_pod(handle, mbps, opts \\ []) do
    node = Keyword.get(opts, :node, "box-1")
    region = Keyword.get(opts, :region, @region)

    %{
      "metadata" => %{"labels" => %{"tuist.dev/account" => handle, "tuist.dev/region" => region}},
      "status" => %{"phase" => Keyword.get(opts, :phase, "Running")},
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

  # us-east sizes per plan, bin-packs the memory ceiling, reserves the
  # Enterprise egress floor and runs two replicas, so an Enterprise instance
  # asks the pool for two replicas of: 16Gi of disk, 1024 MiB of memory and a
  # 4096 MiB ceiling, 100m of CPU and 25 Mbps.
  describe "room_for?/2" do
    test "has room when one node covers every replica of the instance" do
      stub_pool([pool_box("box-1")])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "counts the claim once per replica, as the disk will" do
      # 30 GiB left takes one Enterprise replica, and there is no other node
      # for the second. Pro's two 8Gi claims fit.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "70Gi"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
      assert Capacity.room_for?(@region, :pro) == true
    end

    test "places replicas split across nodes, since the affinity only prefers co-location" do
      # Neither box takes both Enterprise replicas; each takes one, and the
      # scheduler will split them rather than leave the instance Pending.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "80Gi"})]
        ),
        pool_box("box-2",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "80Gi"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "bounds every read, so a hanging apiserver costs seconds" do
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

      stub(Client, :list_nodes, fn _selector, opts ->
        assert opts[:timeout] == to_timeout(second: 5)
        {:ok, %{"items" => [pool_node(pool_box("box-1"))]}}
      end)

      stub(Client, :list_pods_on_node, fn "box-1", opts ->
        assert opts[:timeout] == to_timeout(second: 5)
        {:ok, []}
      end)

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "counts every pod on the node against it, whoever owns it" do
      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "40Gi"}), pool_pod(%{"ephemeral-storage" => "40Gi"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "any node with room is enough" do
      stub_pool([
        pool_box("full",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "90Gi"})]
        ),
        pool_box("empty")
      ])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "reads cpu in cores, fractions and millicores" do
      # Two replicas at the 100m cold start need 200m; 150m is left here.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"cpu" => "4"},
          pods: [pool_pod(%{"cpu" => "2"}), pool_pod(%{"cpu" => "1.5"}), pool_pod(%{"cpu" => "350m"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false

      stub_pool([
        pool_box("box-1",
          allocatable: %{"cpu" => "4"},
          pods: [pool_pod(%{"cpu" => "2"}), pool_pod(%{"cpu" => "1.5"}), pool_pod(%{"cpu" => "300m"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "reserves the plan's memory floor" do
      # 1536 MiB left: Enterprise's two 1024 MiB floors do not fit, Pro's two
      # 512 MiB floors do.
      stub_pool([pool_box("box-1", allocatable: %{"memory" => "3Gi"}, pods: [pool_pod(%{"memory" => "1536Mi"})])])

      assert Capacity.room_for?(@region, :enterprise) == false
      assert Capacity.room_for?(@region, :pro) == true
    end

    test "reserves the egress floor for Enterprise alone" do
      # 35 Mbps left against two 25 Mbps floors. Pro reserves none.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"tuist.dev/egress-mbps" => "60"},
          pods: [pool_pod(%{"tuist.dev/egress-mbps" => "25"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
      assert Capacity.room_for?(@region, :pro) == true
    end

    test "bin-packs the memory ceiling only where a node advertises it" do
      # Two Enterprise ceilings are 8192 MiB; the box advertises 6144.
      stub_pool([pool_box("box-1", allocatable: %{"tuist.dev/memory-ceiling-mib" => "6144"})])

      assert Capacity.room_for?(@region, :enterprise) == false

      # A pool the provider has not patched advertises no budget, and the
      # controller omits the request rather than leaving the pod Pending.
      stub_pool([pool_box("box-1", without: ["tuist.dev/memory-ceiling-mib"])])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "reads the ceiling budget from every node the selector matches, as the controller does" do
      # Only the cordoned box advertises the budget. The controller lists every
      # matching node, finds it, and puts the request on the pod, which the
      # Ready box cannot then take. Reading only the schedulable nodes would
      # omit the request and report room the scheduler will not find.
      stub_pool([
        pool_box("ready", without: ["tuist.dev/memory-ceiling-mib"]),
        pool_box("cordoned", unschedulable?: true)
      ])

      assert Capacity.room_for?(@region, :enterprise) == false

      stub_pool([
        pool_box("ready", without: ["tuist.dev/memory-ceiling-mib"]),
        pool_box("restarting", ready?: false)
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "reserves a pod's initialization peak, as the scheduler does" do
      # The neighbour's app container asks for 500m, its init container for
      # 3900m. The scheduler reserves the larger of the two moments, so the
      # four-core box has 100m left, not 3500m, and two 100m replicas do not fit.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"cpu" => "4"},
          pods: [pool_pod(%{"cpu" => "500m"}, init: [%{"cpu" => "3900m"}])]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false

      stub_pool([
        pool_box("box-1",
          allocatable: %{"cpu" => "4"},
          pods: [pool_pod(%{"cpu" => "500m"}, init: [%{"cpu" => "3400m"}])]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "adds a sidecar to what the pod holds for its whole life" do
      # A sidecar is an init container that keeps running, so it counts with
      # the app rather than only during initialization: 500m + 1400m on a
      # two-core box leaves 100m, short of the 200m two replicas need.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"cpu" => "2"},
          pods: [pool_pod(%{"cpu" => "500m"}, init: [%{"cpu" => "1400m", "restartPolicy" => "Always"}])]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "adds pod overhead" do
      # 500m of app plus 1400m of runtime overhead on a two-core box leaves
      # 100m, short of the 200m two replicas need.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"cpu" => "2"},
          pods: [pool_pod(%{"cpu" => "500m"}, overhead: %{"cpu" => "1400m"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "takes a pod slot per replica, which the scheduler fits against like any resource" do
      # 109 of the box's 110 slots are taken. One replica would schedule; the
      # second is refused with Too many pods, however much CPU and disk is
      # left.
      stub_pool([pool_box("box-1", pods: List.duplicate(pool_pod(%{}), 109))])

      assert Capacity.room_for?(@region, :enterprise) == false

      stub_pool([pool_box("box-1", pods: List.duplicate(pool_pod(%{}), 108))])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "reads a quantity in every form the API keeps it in" do
      # A node whose eviction threshold is a percentage advertises its disk in
      # milli-bytes; a box can quote its disk with a decimal suffix or an
      # exponent; a pod can ask for a fraction of a binary unit or for cores in
      # nanocores. Reading any of them as zero would call an empty box full.
      for allocatable <- ["858993459200000m", "800e9", "800G", "0.8T"] do
        stub_pool([pool_box("box-1", allocatable: %{"ephemeral-storage" => allocatable})])

        assert Capacity.room_for?(@region, :enterprise) == true,
               "expected #{allocatable} of disk to hold the instance"
      end

      # 3.5 GiB less 1.5 GiB leaves exactly the 2048 MiB two Enterprise
      # floors need; 250000000n of cpu is a quarter core.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"memory" => "3.5Gi", "cpu" => "0.45"},
          pods: [pool_pod(%{"memory" => "1.5Gi", "cpu" => "250000000n"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == true

      stub_pool([
        pool_box("box-1",
          allocatable: %{"memory" => "3.5Gi", "cpu" => "0.44"},
          pods: [pool_pod(%{"memory" => "1.5Gi", "cpu" => "250000000n"})]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "is unknown, not full, when a node advertises a quantity it cannot read" do
      stub_pool([pool_box("box-1", allocatable: %{"ephemeral-storage" => "plenty"})])

      assert Capacity.room_for?(@region, :enterprise) == nil
    end

    test "ignores a pod that has finished, which holds nothing" do
      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "90Gi"}, phase: "Failed")]
        )
      ])

      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "does not place on a cordoned node" do
      stub_pool([
        pool_box("full",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "90Gi"})]
        ),
        pool_box("cordoned", unschedulable?: true)
      ])

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "is unknown when the cluster cannot be read" do
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
      stub(Client, :list_nodes, fn _selector, _opts -> {:error, :unavailable} end)

      assert Capacity.room_for?(@region, :enterprise) == nil
    end

    # A box restarting is NotReady for minutes, and a placement taken against
    # that reading would outlast the restart by the life of the account.
    test "is unknown, not full, while no node in the pool is Ready" do
      stub_pool([pool_box("box-1", ready?: false)])

      assert Capacity.room_for?(@region, :enterprise) == nil
    end

    test "is unknown when a node's pods cannot be listed" do
      stub_pool([pool_box("box-1")])
      stub(Client, :list_pods_on_node, fn _node, _opts -> {:error, :unavailable} end)

      assert Capacity.room_for?(@region, :enterprise) == nil
    end
  end

  # `room_for?/2` reads each node of the pool and everything scheduled on it,
  # so shaping a region here means answering both lists.
  defp stub_pool(boxes) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Client, :list_nodes, fn _selector, _opts -> {:ok, %{"items" => Enum.map(boxes, &pool_node/1)}} end)

    stub(Client, :list_pods_on_node, fn name, _opts ->
      case Enum.find(boxes, &(&1.name == name)) do
        %{pods: pods} -> {:ok, pods}
        nil -> {:error, :not_found}
      end
    end)
  end

  # A box with room for many instances on every resource unless told otherwise,
  # so a test that fills one resource is testing that resource.
  defp pool_box(name, opts \\ []) do
    allocatable =
      %{
        "cpu" => "32",
        "memory" => "128Gi",
        "ephemeral-storage" => "800Gi",
        "tuist.dev/memory-ceiling-mib" => "262144",
        "tuist.dev/egress-mbps" => "1500",
        "pods" => "110"
      }
      |> Map.merge(Keyword.get(opts, :allocatable, %{}))
      |> Map.drop(Keyword.get(opts, :without, []))

    %{
      name: name,
      ready?: Keyword.get(opts, :ready?, true),
      unschedulable?: Keyword.get(opts, :unschedulable?, false),
      allocatable: allocatable,
      pods: Keyword.get(opts, :pods, [])
    }
  end

  defp pool_node(box) do
    %{
      "metadata" => %{"name" => box.name},
      "spec" => %{"unschedulable" => box.unschedulable?},
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => if(box.ready?, do: "True", else: "False")}],
        "allocatable" => box.allocatable
      }
    }
  end

  defp pool_pod(requests, opts \\ []) do
    init_containers =
      opts
      |> Keyword.get(:init, [])
      |> Enum.map(fn init ->
        {restart_policy, init_requests} = Map.pop(init, "restartPolicy")

        Map.merge(
          %{"resources" => %{"requests" => init_requests}},
          if(restart_policy, do: %{"restartPolicy" => restart_policy}, else: %{})
        )
      end)

    spec =
      Map.merge(
        %{"containers" => [%{"resources" => %{"requests" => requests}}], "initContainers" => init_containers},
        if(overhead = Keyword.get(opts, :overhead), do: %{"overhead" => overhead}, else: %{})
      )

    %{"status" => %{"phase" => Keyword.get(opts, :phase, "Running")}, "spec" => spec}
  end

  # The scheduler places each replica whole on one node, so a region with room
  # in aggregate is not a region that can take an instance. These read the same
  # nodes `reserved_gib/1` sums, one at a time.
  describe "placeable?/2" do
    test "refuses an instance the region has aggregate room for and no node can take" do
      # 30 GiB left across three boxes covers two 12Gi replicas on paper, and
      # takes neither of them: the scheduler does not split a replica.
      stub_placement([
        placement_box("box-1", "100Gi", [{"neighbour", 90}]),
        placement_box("box-2", "100Gi", [{"neighbour", 90}]),
        placement_box("box-3", "100Gi", [{"neighbour", 90}])
      ])

      assert Capacity.placeable?(region(), %Server{account: placement_account(), storage_claim_size: "12Gi"}) ==
               false
    end

    test "has room when one node covers every replica" do
      stub_placement([placement_box("box-1", "100Gi", [])])

      assert Capacity.placeable?(region(), %Server{account: placement_account(), storage_claim_size: "40Gi"}) ==
               true
    end

    test "counts back what the instance's own replicas release" do
      # 40 GiB left with the account's own two 30Gi replicas on the box. The
      # rebuild hands those 60 GiB back, which is the only reason two 40Gi
      # replicas fit.
      account = placement_account()
      stub_placement([placement_box("box-1", "100Gi", [{handle(account), 30}, {handle(account), 30}])])

      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == true
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "55Gi"}) == false
    end

    test "refuses a raise the instance's own box cannot take, however empty its siblings are" do
      # The 2026-09-11 refusal: the region had hundreds of gibibytes free on
      # another box, and both replicas were pinned by their local volumes to
      # the one that could not hold them at the new size.
      account = placement_account()

      stub_placement([
        placement_box("roomy", "800Gi", []),
        placement_box("pinned", "100Gi", [{handle(account), 30}, {handle(account), 30}])
      ])

      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "60Gi"}) == false
    end

    test "counts every pod on the node against it, whoever owns it" do
      # 35 GiB left on the box and 25 of it taken by a neighbour. The account's
      # own 40 comes back on the rebuild; the neighbour's does not, and it is
      # what decides a 38Gi raise the box would otherwise take.
      account = placement_account()

      stub_placement([
        placement_box("box-1", "100Gi", [{"neighbour", 25}, {handle(account), 20}, {handle(account), 20}])
      ])

      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "37Gi"}) == true
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "38Gi"}) == false
    end

    test "judges a placed instance only where its volumes already are" do
      # One replica of the two placed, and no room for the second. That replica
      # was Pending before this claim moved and stays Pending after it, so
      # refusing the raise would block the account's growth over a condition the
      # raise neither caused nor worsens.
      account = placement_account()

      stub_placement([placement_box("box-1", "100Gi", [{"neighbour", 60}, {handle(account), 20}])])

      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == true
    end

    test "ignores a pod that has finished, which holds nothing" do
      stub_placement([placement_box("box-1", "100Gi", [{"neighbour", 80, [phase: "Failed"]}])])

      assert Capacity.placeable?(region(), %Server{account: placement_account(), storage_claim_size: "40Gi"}) ==
               true
    end

    test "resolves the account's pods from the row when it carries no preload" do
      account = placement_account()
      stub_placement([placement_box("box-1", "100Gi", [{handle(account), 30}, {handle(account), 30}])])

      assert Capacity.placeable?(region(), %Server{account_id: account.id, storage_claim_size: "40Gi"}) == true
    end

    test "leaves every reading it cannot take unknown rather than full" do
      account = placement_account()

      # A box restarting is NotReady for minutes, and refusing every claim the
      # fleet grows in that window is the failure this reading exists to avoid.
      stub_placement([placement_box("box-1", "100Gi", [], ready?: false)])
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == nil

      stub_placement([placement_box("box-1", "100Gi", [])])
      stub(Client, :list_nodes, fn _selector, _opts -> {:error, :unavailable} end)
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == nil

      stub_placement([placement_box("box-1", "100Gi", [])])
      stub(Client, :list_pods, fn _namespace, _selector, _opts -> {:error, :unavailable} end)
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == nil

      # A node whose allocatable this cannot parse would otherwise read as a
      # node with nothing on it, which is the direction that refuses.
      stub_placement([placement_box("box-1", "eight hundred", [])])
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == nil

      # Pods on a node the region's Ready set does not contain cannot be
      # weighed against it.
      stub_placement([placement_box("box-1", "100Gi", []), placement_box("gone", "100Gi", [], ready?: false)])
      stub_account_placement([{"gone", handle(account), 30}])
      assert Capacity.placeable?(region(), %Server{account: account, storage_claim_size: "40Gi"}) == nil
    end

    test "is unknown for a row whose account cannot be named" do
      stub_placement([placement_box("box-1", "100Gi", [])])

      assert Capacity.placeable?(region(), %Server{storage_claim_size: "40Gi"}) == nil
    end

    test "bounds every read, so a hanging apiserver costs seconds" do
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

      stub(Client, :list_nodes, fn _selector, opts ->
        assert opts[:timeout] == to_timeout(second: 5)
        {:ok, %{"items" => [placement_node(placement_box("box-1", "100Gi", []))]}}
      end)

      stub(Client, :list_pods, fn "kura", _selector, opts ->
        assert opts[:timeout] == to_timeout(second: 5)
        {:ok, []}
      end)

      assert Capacity.placeable?(region(), %Server{account: placement_account(), storage_claim_size: "40Gi"}) ==
               true
    end
  end

  defp placement_account, do: account()

  defp handle(%Account{name: name}), do: String.downcase(name)

  # A box, what it makes allocatable, and the claims pinned to it as
  # `{account_handle, gib}` or `{account_handle, gib, pod_opts}`.
  defp placement_box(name, allocatable, claims, opts \\ []) do
    %{name: name, allocatable: allocatable, claims: claims, ready?: Keyword.get(opts, :ready?, true)}
  end

  defp stub_placement(boxes) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

    stub(Client, :list_nodes, fn _selector, _opts ->
      {:ok, %{"items" => Enum.map(boxes, &placement_node/1)}}
    end)

    pods =
      Enum.flat_map(boxes, fn box ->
        Enum.map(box.claims, fn claim ->
          {owner, gib, opts} =
            case claim do
              {owner, gib} -> {owner, gib, []}
              {owner, gib, opts} -> {owner, gib, opts}
            end

          placement_pod(owner, gib, box.name, opts)
        end)
      end)

    stub(Client, :list_pods, fn "kura", selector, _opts -> {:ok, matching(pods, selector)} end)
  end

  # Pods of one account on a node the region's node list does not answer for.
  defp stub_account_placement(claims) do
    pods = Enum.map(claims, fn {node, owner, gib} -> placement_pod(owner, gib, node) end)

    stub(Client, :list_pods, fn "kura", selector, _opts -> {:ok, matching(pods, selector)} end)
  end

  defp matching(pods, selector) do
    case Regex.run(~r{tuist\.dev/account=([^,]+)}, selector) do
      [_match, handle] -> Enum.filter(pods, &(&1["metadata"]["labels"]["tuist.dev/account"] == handle))
      nil -> pods
    end
  end

  defp placement_node(box) do
    %{
      "metadata" => %{"name" => box.name},
      "status" => %{
        "conditions" => [%{"type" => "Ready", "status" => if(box.ready?, do: "True", else: "False")}],
        "allocatable" => %{"ephemeral-storage" => box.allocatable}
      }
    }
  end

  defp placement_pod(owner, gib, node, opts \\ []) do
    %{
      "metadata" => %{"labels" => %{"tuist.dev/account" => owner}},
      "status" => %{"phase" => Keyword.get(opts, :phase, "Running")},
      "spec" => %{
        "nodeName" => node,
        "containers" => [%{"resources" => %{"requests" => %{"ephemeral-storage" => "#{gib}Gi"}}}]
      }
    }
  end
end
