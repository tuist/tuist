defmodule Tuist.Kura.CapacityTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Kura.Admission
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
  @pressure_line_gib trunc(@allocatable_gib * 0.85)
  # us-east co-locates an account's two replicas on one box, so a new instance
  # reserves its plan's starting claim twice.
  @air_instance_gib 8 * 2
  @enterprise_instance_gib 16 * 2

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

  defp new_instance(claim_size), do: %Server{region: @region, status: :provisioning, storage_claim_size: claim_size}

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
    setup do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      :ok
    end

    test "is false while the region has room for a new instance of any plan" do
      installed(1)
      stub_region_pods([reserved_pod(50)])

      refute Capacity.under_pressure?(@region)
    end

    test "engages while admission still admits, once a new enterprise instance no longer fits" do
      installed(1)
      stub_region_pods([reserved_pod(@pressure_line_gib - @air_instance_gib)])

      assert :ok = Admission.admit?(region(), new_instance("8Gi"))
      assert {:error, :capacity_exhausted} = Admission.admit?(region(), new_instance("16Gi"))
      assert Capacity.under_pressure?(@region)
    end

    test "stays off while admission can still take a new enterprise instance" do
      installed(1)
      stub_region_pods([reserved_pod(@pressure_line_gib - @enterprise_instance_gib)])

      assert :ok = Admission.admit?(region(), new_instance("16Gi"))
      refute Capacity.under_pressure?(@region)
    end

    test "counts instances committed before the cluster observes their pods, as admission does" do
      installed(1)
      stub_region_pods([])

      for _ <- 1..div(@pressure_line_gib, @enterprise_instance_gib) do
        account() |> instance() |> Ecto.Changeset.change(storage_claim_size: "16Gi") |> Repo.update!()
      end

      assert Capacity.under_pressure?(@region)
    end

    test "is true once the region has reserved past its pressure line" do
      installed(1)
      stub_region_pods(List.duplicate(reserved_pod(50), div(@allocatable_gib, 50)))

      assert Capacity.under_pressure?(@region)
    end

    test "is false where admission is not enforced" do
      stub(Environment, :kura_capacity_admission_required?, fn -> false end)
      installed(1)
      stub_region_pods(List.duplicate(reserved_pod(50), div(@allocatable_gib, 50)))

      refute Capacity.under_pressure?(@region)
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
    test "leaves kubelet's eviction margin below allocatable" do
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

    test "has no room where admission would refuse the instance, however much the nodes have free" do
      # us-west on 2026-09-17: one box, 789 GiB allocatable, 664 GiB reserved.
      # The box has 125 GiB free, but admission stops at 85% of allocatable,
      # 670 GiB, which leaves 6 GiB against the 16 GiB two Air claims reserve.
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)

      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "789Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "664Gi"})]
        )
      ])

      assert Capacity.room_for?(@region, :air) == false

      # 16 GiB of headroom admits two Air claims and not two Enterprise ones.
      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "789Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "654Gi"})]
        )
      ])

      assert Capacity.room_for?(@region, :air) == true
      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "counts rows admission counts that no pod holds yet" do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      stub_pool([pool_box("box-1", allocatable: %{"ephemeral-storage" => "100Gi"})])

      # 85 GiB of headroom less a provisioning Enterprise instance's 32.
      account = account(:enterprise)
      instance(account, :provisioning)

      assert Capacity.room_for?(@region, :enterprise) == true

      instance(account(:enterprise), :provisioning)

      assert Capacity.room_for?(@region, :enterprise) == false
    end

    test "reads the nodes alone where admission is not enforced" do
      stub(Environment, :kura_capacity_admission_required?, fn -> false end)

      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "789Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "664Gi"})]
        )
      ])

      assert Capacity.room_for?(@region, :air) == true
    end

    test "is unknown, not full, when admission cannot read the region the nodes have room in" do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      stub_pool([pool_box("box-1")])
      stub(Client, :list_pods, fn _namespace, _selector -> {:error, :unavailable} end)

      assert Capacity.room_for?(@region, :enterprise) == nil
    end

    test "is full when the nodes are, whether or not admission can read the region" do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)

      stub_pool([
        pool_box("box-1",
          allocatable: %{"ephemeral-storage" => "100Gi"},
          pods: [pool_pod(%{"ephemeral-storage" => "90Gi"})]
        )
      ])

      stub(Client, :list_pods, fn _namespace, _selector -> {:error, :unavailable} end)

      assert Capacity.room_for?(@region, :enterprise) == false
    end
  end

  describe "admission_headroom_gib/1" do
    test "is the reading room_for?/2 places against, taken once a minute per region" do
      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      {:ok, region} = Regions.fetch(@region)
      stub_pool([pool_box("box-1", allocatable: %{"ephemeral-storage" => "100Gi"})])
      memoize_key_value_store()

      assert Capacity.admission_headroom_gib(region) == 85

      # Two Enterprise instances are created inside the minute. Measured again,
      # they would leave 21 GiB, too little for a third. Both readings keep the
      # first measurement, so the metric reports what placement acted on.
      instance(account(:enterprise), :provisioning)
      instance(account(:enterprise), :provisioning)

      assert Capacity.admission_headroom_gib(region) == 85
      assert Capacity.room_for?(@region, :enterprise) == true
    end

    test "passes through a region admission cannot read or does not enforce" do
      {:ok, region} = Regions.fetch(@region)
      stub_pool([pool_box("box-1")])
      stub(Client, :list_pods, fn _namespace, _selector -> {:error, :unavailable} end)

      stub(Environment, :kura_capacity_admission_required?, fn -> true end)
      assert Capacity.admission_headroom_gib(region) == nil

      stub(Environment, :kura_capacity_admission_required?, fn -> false end)
      assert Capacity.admission_headroom_gib(region) == :unbounded
    end
  end

  # A key-value store that keeps the first value it computes per key, standing
  # in for the minute-long cache within a single test.
  defp memoize_key_value_store do
    store = start_supervised!({Agent, fn -> %{} end})

    stub(KeyValueStore, :get_or_update, fn key, _opts, func ->
      case Agent.get(store, &Map.fetch(&1, key)) do
        {:ok, value} -> value
        :error -> tap(func.(), fn value -> Agent.update(store, &Map.put(&1, key, value)) end)
      end
    end)
  end

  # `room_for?/2` reads each node of the pool and everything scheduled on it,
  # and admission reads the same region's Ready nodes and pods as a whole, so
  # shaping a region here means answering all four lists.
  defp stub_pool(boxes) do
    stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)
    stub(Client, :list_nodes, fn _selector, _opts -> {:ok, %{"items" => Enum.map(boxes, &pool_node/1)}} end)
    stub(Client, :list_nodes, fn _selector -> {:ok, %{"items" => Enum.map(boxes, &pool_node/1)}} end)
    stub(Client, :list_pods, fn _namespace, _selector -> {:ok, Enum.flat_map(boxes, & &1.pods)} end)

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
  # in aggregate is not a region that can take an instance. These read the
  # same nodes, and everything scheduled on them, that `room_for?/2` reads.
  describe "placeable?/2" do
    test "refuses an instance the region has aggregate room for and no node can take" do
      # 30 GiB left across three boxes covers two 12Gi replicas on paper, and
      # takes neither of them: the scheduler does not split a replica.
      stub_pool([
        disk_box("box-1", 100, [neighbour_pod(90)]),
        disk_box("box-2", 100, [neighbour_pod(90)]),
        disk_box("box-3", 100, [neighbour_pod(90)])
      ])

      assert Capacity.placeable?(region(), claim(placement_account(), "12Gi")) == false
    end

    test "has room when one node covers every replica" do
      stub_pool([disk_box("box-1", 100, [])])

      assert Capacity.placeable?(region(), claim(placement_account(), "50Gi")) == true
    end

    test "counts back what the instance's own replicas release" do
      # 40 GiB left with the account's own two 30Gi replicas on the box. The
      # rebuild hands those 60 GiB back, which is the only reason two 50Gi
      # replicas fit.
      account = placement_account()
      stub_pool([disk_box("box-1", 100, [kura_pod(account, 30), kura_pod(account, 30)])])

      assert Capacity.placeable?(region(), claim(account, "50Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "51Gi")) == false
    end

    test "refuses a raise the instance's own box cannot take, however empty its siblings are" do
      # The 2026-09-11 refusal: the region had hundreds of gibibytes free on
      # another box, and both replicas were pinned by their local volumes to
      # the one that could not hold them at the new size.
      account = placement_account()

      stub_pool([
        disk_box("roomy", 800, []),
        disk_box("pinned", 100, [kura_pod(account, 30), kura_pod(account, 30)])
      ])

      assert Capacity.placeable?(region(), claim(account, "60Gi")) == false
    end

    test "counts every workload on the node against it, in any namespace" do
      # Another namespace's 30Gi is not the region's, and the scheduler will
      # not hand it out twice: two 40Gi replicas would need 110 GiB of a
      # 100 GiB box.
      account = placement_account()

      stub_pool([
        disk_box("box-1", 100, [kura_pod(account, 20), kura_pod(account, 20), neighbour_pod(30)])
      ])

      assert Capacity.placeable?(region(), claim(account, "35Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == false
    end

    test "reads a neighbour at its effective request, initialization included" do
      # The app container asks for 10Gi; initialization needs 50Gi at its
      # busiest, and that is what the scheduler holds on the box.
      account = placement_account()

      stub_pool([
        disk_box("box-1", 100, [
          kura_pod(account, 20),
          kura_pod(account, 20),
          pool_pod(%{"ephemeral-storage" => "10Gi"}, init: [%{"ephemeral-storage" => "50Gi"}])
        ])
      ])

      assert Capacity.placeable?(region(), claim(account, "25Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "26Gi")) == false
    end

    test "answers the same mid-rollout as before it" do
      # A replica between deletion and recreation is in no pod list, and its
      # local volume brings it back to the box it left. With 50 GiB of
      # neighbours, two 40Gi replicas never fit; reading the one that is still
      # there as the whole instance would admit the raise and strand the other.
      account = placement_account()

      stub_pool([disk_box("box-1", 100, [neighbour_pod(50), kura_pod(account, 20), kura_pod(account, 20)])])
      assert Capacity.placeable?(region(), claim(account, "25Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == false

      stub_pool([disk_box("box-1", 100, [neighbour_pod(50), kura_pod(account, 20)])])
      assert Capacity.placeable?(region(), claim(account, "25Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == false
    end

    test "does not charge a box for a replica its sibling box holds" do
      # The affinity only prefers co-location, so an account can straddle two
      # boxes. Each rebuilds its own replica, and box-1 has room for one 30Gi.
      account = placement_account()

      stub_pool([
        disk_box("box-1", 100, [neighbour_pod(70), kura_pod(account, 20)]),
        disk_box("box-2", 100, [kura_pod(account, 20)])
      ])

      assert Capacity.placeable?(region(), claim(account, "30Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "31Gi")) == false
    end

    test "weighs the account's replicas against the same reading their node was measured in" do
      # The reading is cached for a minute. Measured once while the box held
      # only a neighbour, then asked about an account whose replicas have
      # landed since: whatever it answers has to be what a fresh reading says,
      # never free space from one moment plus reservations from another.
      cache = start_supervised!({Agent, fn -> %{} end})

      stub(KeyValueStore, :get_or_update, fn key, _opts, func ->
        case Agent.get(cache, &Map.fetch(&1, key)) do
          {:ok, value} -> value
          :error -> tap(func.(), fn value -> Agent.update(cache, &Map.put(&1, key, value)) end)
        end
      end)

      account = placement_account()
      stub_pool_nodes([disk_box("box-1", 100, [neighbour_pod(60)])])
      Capacity.placeable?(region(), claim(placement_account(), "8Gi"))

      stub_pool_nodes([disk_box("box-1", 100, [neighbour_pod(60), kura_pod(account, 20), kura_pod(account, 20)])])
      cached = Capacity.placeable?(region(), claim(account, "30Gi"))

      Agent.update(cache, fn _entries -> %{} end)

      assert cached == false
      assert Capacity.placeable?(region(), claim(account, "30Gi")) == cached
    end

    test "ignores a pod that has finished, which holds nothing" do
      stub_pool([disk_box("box-1", 100, [neighbour_pod(80, phase: "Failed")])])

      assert Capacity.placeable?(region(), claim(placement_account(), "50Gi")) == true
    end

    test "resolves the account's pods from the row when it carries no preload" do
      account = placement_account()
      stub_pool([disk_box("box-1", 100, [kura_pod(account, 30), kura_pod(account, 30)])])

      assert Capacity.placeable?(region(), %Server{account_id: account.id, storage_claim_size: "50Gi"}) == true
    end

    test "only reads the region's own replicas of the account as its instance" do
      # The same account's instance of another region on this box is a
      # neighbour: it holds its disk, and nothing about this rebuild hands it
      # back.
      account = placement_account()

      stub_pool([
        disk_box("box-1", 100, [kura_pod(account, 30), kura_pod(account, 30, region: "us-west")])
      ])

      assert Capacity.placeable?(region(), claim(account, "35Gi")) == true
      assert Capacity.placeable?(region(), claim(account, "36Gi")) == false
    end

    test "leaves every reading it cannot take unknown rather than full" do
      account = placement_account()

      # A box restarting is NotReady for minutes, and refusing every claim the
      # fleet grows in that window is the failure this reading exists to avoid.
      stub_pool([disk_box("box-1", 100, [], ready?: false)])
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == nil

      stub_pool([disk_box("box-1", 100, [])])
      stub(Client, :list_nodes, fn _selector, _opts -> {:error, :unavailable} end)
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == nil

      stub_pool([disk_box("box-1", 100, [])])
      stub(Client, :list_pods_on_node, fn _node, _opts -> {:error, :unavailable} end)
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == nil

      # A node whose allocatable this cannot parse would otherwise read as a
      # node with nothing on it, which is the direction that refuses.
      stub_pool([pool_box("box-1", allocatable: %{"ephemeral-storage" => "eight hundred"})])
      assert Capacity.placeable?(region(), claim(account, "40Gi")) == nil

      # A replica on a box the scheduler places nothing on cannot be weighed,
      # and charging it to the Ready box instead would refuse on a guess.
      stub_pool([
        disk_box("box-1", 100, [kura_pod(account, 20)]),
        disk_box("cordoned", 100, [kura_pod(account, 20)], unschedulable?: true)
      ])

      assert Capacity.placeable?(region(), claim(account, "40Gi")) == nil
    end

    test "is unknown for a row whose account cannot be named" do
      stub_pool([disk_box("box-1", 100, [])])

      assert Capacity.placeable?(region(), %Server{storage_claim_size: "40Gi"}) == nil
    end

    test "bounds every read, so a hanging apiserver costs seconds" do
      stub(KeyValueStore, :get_or_update, fn _key, _opts, func -> func.() end)

      stub(Client, :list_nodes, fn _selector, opts ->
        assert opts[:timeout] == to_timeout(second: 5)
        {:ok, %{"items" => [pool_node(disk_box("box-1", 100, []))]}}
      end)

      stub(Client, :list_pods_on_node, fn "box-1", opts ->
        assert opts[:timeout] == to_timeout(second: 5)
        {:ok, []}
      end)

      assert Capacity.placeable?(region(), claim(placement_account(), "40Gi")) == true
    end
  end

  defp placement_account, do: account()

  defp claim(%Account{} = account, size), do: %Server{account: account, storage_claim_size: size}

  defp disk_box(name, allocatable_gib, pods, opts \\ []) do
    pool_box(name, Keyword.merge(opts, allocatable: %{"ephemeral-storage" => "#{allocatable_gib}Gi"}, pods: pods))
  end

  # The node list and each node's pods, without the region-wide readings
  # `stub_pool/1` also answers, so a test can drive the cache itself.
  defp stub_pool_nodes(boxes) do
    stub(Client, :list_nodes, fn _selector, _opts -> {:ok, %{"items" => Enum.map(boxes, &pool_node/1)}} end)

    stub(Client, :list_pods_on_node, fn name, _opts ->
      {:ok, boxes |> Enum.find(%{pods: []}, &(&1.name == name)) |> Map.fetch!(:pods)}
    end)
  end

  defp neighbour_pod(gib, opts \\ []), do: pool_pod(%{"ephemeral-storage" => "#{gib}Gi"}, opts)

  # A replica as the controller labels it, on whichever box the test lists it.
  defp kura_pod(%Account{name: name}, gib, opts \\ []) do
    %{"ephemeral-storage" => "#{gib}Gi"}
    |> pool_pod(opts)
    |> Map.put("metadata", %{
      "namespace" => "kura",
      "labels" => %{
        "app.kubernetes.io/managed-by" => "kura-controller",
        "tuist.dev/region" => Keyword.get(opts, :region, @region),
        "tuist.dev/account" => String.downcase(name)
      }
    })
  end
end
