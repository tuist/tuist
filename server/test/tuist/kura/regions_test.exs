defmodule Tuist.Kura.RegionsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions

  setup :set_mimic_from_context

  describe "all/0" do
    test "exposes concrete managed regions backed by KubernetesController" do
      ids = Enum.map(Regions.all(), & &1.id)

      ingress_classes = %{
        "eu-central" => "kura-eu-central",
        "us-east" => "kura-us-east",
        "us-west" => "kura-us-west"
      }

      assert "us-east" in ids
      assert "us-west" in ids
      assert "eu-central" in ids

      for id <- ["us-east", "us-west", "eu-central"] do
        assert %Regions{provisioner: KubernetesController, provisioner_config: config} =
                 Regions.get(id)

        refute Regions.get(id).display_name =~ "Hetzner"
        assert config.cluster_id == "#{id}-1"
        assert config.ingress_class_name == ingress_classes[id]
      end

      # us-east/us-west run on OVH bare metal (hostNetwork gateway, local-NVMe,
      # two replicas); eu-central is on Dedibox bare metal (asserted below).
      for id <- ["us-east", "us-west"] do
        config = Regions.get(id).provisioner_config
        assert config.hetzner_location == nil
        assert config.storage_class == "scw-local-nvme"
        assert config.gateway == :host_network
        assert config.replicas == 2
        assert config.storage_governed == true

        # No region-wide claim: every instance carries the one its volumes were
        # created at, resolved from its account's plan.
        assert config.storage_size == nil
      end

      assert Regions.get("us-east").provisioner_config.node_selector == %{
               "node.cluster.x-k8s.io/pool" => "kura-us-east"
             }

      assert Regions.get("us-west").provisioner_config.node_selector == %{
               "node.cluster.x-k8s.io/pool" => "kura-us-west"
             }

      assert Regions.get("eu-central").provisioner_config.node_selector == %{
               "node.cluster.x-k8s.io/pool" => "kura-dedibox"
             }

      for id <- ["us-east", "us-west", "eu-central"] do
        refute Map.has_key?(Regions.get(id).provisioner_config, :kubernetes_client)
        refute Map.has_key?(Regions.get(id).provisioner_config, :peer_tls_secret_name)
      end
    end

    test "sets a uniform enterprise egress floor across the bare-metal regions" do
      for id <- ["us-east", "us-west", "eu-central", "ca-east", "ap-southeast"] do
        assert Regions.get(id).provisioner_config.egress_guaranteed_mbps == 25
      end

      # The burst ceiling stays per-box and rides the pod annotation.
      assert Regions.get("us-east").provisioner_config.pod_annotations == %{
               "kubernetes.io/egress-bandwidth" => "1500M"
             }
    end

    test "sizes the managed regions per tier" do
      # Safe here and not before: a tiered floor sits far below its ceiling, so
      # it is only a scheduling promise until the kubelet's MemoryQoS gate makes
      # it the pod's cgroup memory.min. That gate ships in this same change.
      for id <- ["us-east", "us-west", "eu-central", "ca-east", "ap-southeast"] do
        assert Regions.memory_governed?(Regions.get(id))
      end

      refute Regions.memory_governed?(Regions.get("scw-fr-par-runners"))
    end

    test "bin-packs memory ceilings only where a node budget is advertised" do
      # Every managed region runs on a bare-metal pool the CAPI provider patches
      # with a tuist.dev/memory-ceiling-mib budget.
      for id <- ["us-east", "us-west", "eu-central", "ca-east", "ap-southeast"] do
        assert Regions.memory_ceiling_bin_packed?(Regions.get(id))
      end

      # The private runner-cache pool runs on Elastic Metal, which the provider
      # does not patch; requesting the extended resource there would leave every
      # cache pod Pending.
      refute Regions.memory_ceiling_bin_packed?(Regions.get("scw-fr-par-runners"))
    end

    test "sizes the managed regions' storage per tier" do
      for id <- ["us-east", "us-west", "eu-central", "ca-east", "ap-southeast"] do
        assert Regions.storage_governed?(Regions.get(id))
      end

      # The private runner-cache pool holds one instance per account regardless
      # of plan, on capacity ordered for the runner fleet.
      refute Regions.storage_governed?(Regions.get("scw-fr-par-runners"))
      refute Regions.storage_governed?(Regions.get("local-controller"))
    end

    test "descends the storage ladder and floors it at air" do
      claims = Enum.map([:enterprise, :pro, :air], &Regions.storage_profile(&1).claim_size)
      assert claims == ["50Gi", "30Gi", "8Gi"]

      # Air is the floor, and unknown plans land on it.
      assert Regions.storage_profile(:open_source) == Regions.storage_profile(:air)
    end

    test "bounds an operator override by the floor the ladder already sits on" do
      # One floor, not two. A hand-typed override is the one claim that can land
      # under the reserve, and the bound it is held to is air's claim rather than
      # a number of its own, so the budget-cliff test above covers it: whatever
      # clears the derivation for air clears it for the smallest override.
      assert Regions.minimum_storage_claim() == Regions.storage_profile(:air).claim_size

      {:ok, minimum_bytes} = Regions.parse_storage_quantity(Regions.minimum_storage_claim())

      for plan <- [:enterprise, :pro, :air, :open_source] do
        {:ok, claim_bytes} = Regions.parse_storage_quantity(Regions.storage_profile(plan).claim_size)

        assert claim_bytes >= minimum_bytes
      end
    end

    test "parses the storage quantities a claim is written in" do
      assert Regions.parse_storage_quantity("14Gi") == {:ok, 14 * 1024 * 1024 * 1024}
      assert Regions.parse_storage_quantity("1Ti") == {:ok, 1024 * 1024 * 1024 * 1024}
      assert Regions.parse_storage_quantity("512Mi") == {:ok, 512 * 1024 * 1024}
      assert Regions.parse_storage_quantity("1024") == {:ok, 1024}

      for value <- ["", "0Gi", "-4Gi", "24GB", "big", nil] do
        assert Regions.parse_storage_quantity(value) == :error
      end
    end

    test "keeps every claim clear of the budget cliff" do
      # Staging and one rotation segment come out of a claim before the ring is
      # sized, and Kura clamps its ring up to five segments. A claim too small to
      # clear that leaves `cas_capacity_bytes/1` emitting nothing at all, and the
      # runtime sizes its ring from the whole box instead — the failure the
      # derivation exists to prevent. Asserted against the derivation rather than
      # a claim number, so it still holds if the reserves move.
      gib = 1024 * 1024 * 1024
      kura_ring_floor = 5 * 512 * 1024 * 1024

      for plan <- [:enterprise, :pro, :air, :open_source] do
        {claim_gib, "Gi"} = Integer.parse(Regions.storage_profile(plan).claim_size)
        staging = min(div(claim_gib * gib, 2), 8 * gib)
        ring = div((claim_gib * gib - staging - 512 * 1024 * 1024) * 97, 100)

        assert ring >= kura_ring_floor * 5 / 4,
               "#{plan} leaves #{ring} bytes of ring, too close to Kura's #{kura_ring_floor} floor"
      end
    end

    test "keeps every memory ceiling above its floor" do
      # A limit below its request is rejected by the API, and a ceiling equal to
      # the floor would leave no burst headroom for Kura's admission pools.
      for plan <- [:enterprise, :pro, :air, :open_source] do
        %{floor_mib: floor_mib, ceiling_mib: ceiling_mib} = Regions.memory_profile(plan)
        assert ceiling_mib > floor_mib
      end

      # Floors are what decide how many tenants fit on a box, so the ladder has
      # to actually descend to be worth tiering at all.
      floors = Enum.map([:enterprise, :pro, :air], &Regions.memory_profile(&1).floor_mib)
      assert floors == Enum.sort(floors, :desc)
      assert Enum.uniq(floors) == floors

      # Each ceiling has to clear its plan's measured peak by more than the
      # runtime's 0.9x recovery hysteresis, or a burst that trips shedding stays
      # shedding. Peaks: ~1220 MiB for the busiest pro instance, ~150 MiB for air.
      for {plan, peak_mib} <- [pro: 1220, air: 150] do
        soft = Regions.memory_profile(plan).ceiling_mib * 0.6
        assert soft * 0.9 > peak_mib, "#{plan} recovers at #{soft * 0.9} MiB, under its #{peak_mib} MiB peak"
      end
    end

    test "runs eu-central on Dedibox bare metal" do
      config = Regions.get("eu-central").provisioner_config

      assert config.node_selector == %{"node.cluster.x-k8s.io/pool" => "kura-dedibox"}
      assert config.storage_class == "scw-local-nvme"
      assert config.gateway == :host_network
      assert config.replicas == 2
      assert config.storage_size == nil
      assert config.hetzner_location == nil

      # Identity is unchanged so the cutover is invisible to the customer and CLI.
      assert config.cluster_id == "eu-central-1"
      assert config.ingress_class_name == "kura-eu-central"
      assert Regions.get("eu-central").display_name == "EU Central"
    end

    test "threads the per-region public peer failover IP from the environment" do
      stub(Tuist.Environment, :kura_peer_failover_ip, fn
        "eu-central" -> "203.0.113.10"
        _ -> nil
      end)

      assert Regions.get("eu-central").provisioner_config.failover_ip == "203.0.113.10"
      assert Regions.get("us-east").provisioner_config.failover_ip == nil
    end

    test "enables the per-account peer mesh on managed and private regions" do
      for id <- ["us-east", "us-west", "eu-central", "ca-east", "scw-fr-par-runners"] do
        assert Regions.get(id).provisioner_config.mesh == true,
               "expected region #{id} to enable the peer mesh"
      end
    end

    test "tolerates the runner-cache node taint only on the scaleway runner-cache region" do
      assert Regions.get("scw-fr-par-runners").provisioner_config.tolerations == [
               %{"key" => "tuist.dev/runner-cache", "operator" => "Exists", "effect" => "NoSchedule"}
             ]

      # The customer-facing cache pools carry their own taint, not the
      # runner-cache one, so their regions never tolerate it.
      assert Regions.get("eu-central").provisioner_config.tolerations == [
               %{"key" => "tuist.dev/kura-cache", "operator" => "Exists", "effect" => "NoSchedule"}
             ]
    end

    test "exposes a local controller-backed region for kind smoke tests" do
      assert %Regions{
               id: "local-controller",
               provisioner: KubernetesController,
               provisioner_config: config
             } =
               Enum.find(Regions.all(), &(&1.id == "local-controller"))

      assert config.cluster_id == "local-controller"
      assert config.kubernetes_client[:mode] == :kubeconfig
      assert config.kubernetes_client[:kubeconfig_path] == Path.expand("~/.kube/config")
      assert String.starts_with?(config.kubernetes_client[:context], "kind-kura-dev-")
      assert config.replicas == 1
      assert config.storage_size == "10Gi"
      assert config.node_selector == %{"kubernetes.io/os" => "linux"}
    end

    test "weaves a per-environment suffix into managed-region public hostnames" do
      stub(Tuist.Environment, :env, fn -> :stag end)

      config = Regions.get("eu-central").provisioner_config

      assert config.public_host_template == "{account_handle}-{cluster_id}-staging.kura.tuist.dev"

      # gRPC co-hosts on the single public host (no separate grpc. hostname).
      assert config.grpc_public_host_template == config.public_host_template

      stub(Tuist.Environment, :env, fn -> :can end)

      canary_config = Regions.get("us-east").provisioner_config

      assert canary_config.public_host_template ==
               "{account_handle}-{cluster_id}-canary.kura.tuist.dev"

      assert canary_config.grpc_public_host_template == canary_config.public_host_template
    end

    test "omits the environment suffix from managed-region public hostnames in production" do
      stub(Tuist.Environment, :env, fn -> :prod end)

      config = Regions.get("eu-central").provisioner_config

      assert config.public_host_template == "{account_handle}-{cluster_id}.kura.tuist.dev"

      assert config.grpc_public_host_template == config.public_host_template
    end

    test "reads the managed-region Tuist base URL from the environment adapter" do
      stub(Tuist.Environment, :kura_tuist_base_url, fn ->
        "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"
      end)

      assert Regions.get("eu-central").provisioner_config.tuist_base_url ==
               "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"
    end

    test "keeps managed regions aligned with platform ingress classes and production node pools" do
      platform_values = read_repo_yaml("infra/helm/platform/values.yaml")
      production_cluster = read_repo_yaml("infra/k8s/clusters/cluster-production.yaml")

      platform_ingress_keys = %{
        "eu-central" => "kura-eu-central-ingress-nginx",
        "us-east" => "kura-us-east-ingress-nginx",
        "us-west" => "kura-us-west-ingress-nginx"
      }

      for {id, platform_ingress_key} <- platform_ingress_keys do
        assert %Regions{provisioner_config: config} = Regions.get(id)
        node_pool = config.node_selector["node.cluster.x-k8s.io/pool"]

        assert get_in(platform_values, [
                 platform_ingress_key,
                 "controller",
                 "ingressClass"
               ]) == config.ingress_class_name

        assert get_in(platform_values, [
                 platform_ingress_key,
                 "controller",
                 "ingressClassResource",
                 "name"
               ]) == config.ingress_class_name

        assert production_node_pool_location(production_cluster, node_pool) ==
                 config.hetzner_location
      end
    end
  end

  describe "node_location/1" do
    test "gives every provisionable region the location of the datacenter it runs in" do
      locations = %{
        # OVH Vint Hill VA / Hillsboro OR, Scaleway Dedibox (Paris region),
        # OVHcloud BHS in Quebec, Scaleway Elastic Metal fr-par.
        "us-east" => %{country: "US", subdivision: "US-VA"},
        "us-west" => %{country: "US", subdivision: "US-OR"},
        "eu-central" => %{country: "FR", subdivision: "FR-IDF"},
        "ca-east" => %{country: "CA", subdivision: "CA-QC"},
        "scw-fr-par-runners" => %{country: "FR", subdivision: "FR-IDF"},
        # Singapore is a city-state: its ISO 3166-2 codes are CDC statistical
        # districts rather than anything a datacenter address resolves to, so
        # the country alone is the whole location and the subdivision is left
        # unstated instead of guessed.
        "ap-southeast" => %{country: "SG", subdivision: nil}
      }

      for {id, location} <- locations do
        assert Regions.node_location(Regions.get(id)) == location
      end
    end

    test "leaves no provisionable region without one" do
      # Kura cannot work its own location out any more, so a fleet that ships
      # without this exports every span with no geography and nothing detects
      # it. The local controller region is a developer's own machine, and
      # tombstones never provision, so neither declares a location.
      unlocated =
        Regions.all()
        |> Enum.reject(&(&1.id == "local-controller" or Regions.retired?(&1)))
        |> Enum.filter(&is_nil(Regions.node_location(&1)))

      assert unlocated == []
    end

    test "returns nil for a region that declares no location" do
      # Two different shapes reach nil. The local controller omits the keys
      # entirely, while a tombstone carries them as nil, because the region
      # builders write both unconditionally through Map.get/2. Any future
      # region added without a location takes the tombstone's path, so it is
      # the one that has to keep resolving rather than raising.
      assert Regions.node_location(Regions.get("local-controller")) == nil
      assert Regions.node_location(Regions.get("hetzner-staging-runners")) == nil
    end
  end

  describe "available/0" do
    test "returns only the controller-backed local region in test" do
      assert Enum.map(Regions.available(), & &1.id) == ["local-controller"]
    end

    test "returns only configured managed regions outside test and development" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.Environment, :kura_available_region_ids, fn -> ["eu-central"] end)

      assert Enum.map(Regions.available(), & &1.id) == ["eu-central"]
    end

    test "returns every configured managed region outside test and development" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      stub(Tuist.Environment, :kura_available_region_ids, fn ->
        ["eu-central", "us-east", "us-west"]
      end)

      assert Enum.map(Regions.available(), & &1.id) == ["us-east", "us-west", "eu-central"]
    end

    test "ignores unknown configured managed regions" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.Environment, :kura_available_region_ids, fn -> ["eu-central", "unknown"] end)

      assert Enum.map(Regions.available(), & &1.id) == ["eu-central"]
    end

    test "never makes a retired cleanup region available" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      stub(Tuist.Environment, :kura_available_region_ids, fn ->
        ["hetzner-staging-runners"]
      end)

      assert Regions.available() == []
    end
  end

  describe "ap-southeast" do
    test "is a single-replica bare-metal region on its own OVH node pool" do
      assert %Regions{provisioner: KubernetesController, provisioner_config: config} =
               Regions.get("ap-southeast")

      assert Regions.get("ap-southeast").display_name == "Asia Pacific Southeast"
      assert config.cluster_id == "ap-southeast-1"
      assert config.ingress_class_name == "kura-ap-southeast"
      assert config.node_selector == %{"node.cluster.x-k8s.io/pool" => "kura-ap-southeast"}
      assert config.storage_class == "scw-local-nvme"
      assert config.gateway == :host_network
      assert config.hetzner_location == nil

      # One box, so one replica. The warm standby the other bare-metal regions
      # carry only buys gapless deploys on a region with room to hold both.
      assert config.replicas == 1

      # No region-wide claim: every instance carries the one its volumes were
      # created at, resolved from its account's plan.
      assert config.storage_size == nil
    end

    test "takes the conservative burst ceiling until the box's NIC is measured" do
      assert Regions.get("ap-southeast").provisioner_config.pod_annotations == %{
               "kubernetes.io/egress-bandwidth" => "500M"
             }
    end

    test "is served only where TUIST_KURA_AVAILABLE_REGIONS names it" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      # Production's list today. The region is in the catalog, so it has to be
      # the gate that keeps it unserved rather than its absence from the
      # catalog — there is a fleet definition waiting on hardware behind it.
      stub(Tuist.Environment, :kura_available_region_ids, fn ->
        ["eu-central", "us-east", "us-west", "scw-fr-par-runners"]
      end)

      refute Regions.available?("ap-southeast")
      refute "ap-southeast" in Enum.map(Regions.selectable(), & &1.id)
    end

    test "becomes available and selectable once the gate names it" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      stub(Tuist.Environment, :kura_available_region_ids, fn ->
        ["us-east", "ap-southeast"]
      end)

      assert Regions.available?("ap-southeast")
      assert Enum.map(Regions.available(), & &1.id) == ["us-east", "ap-southeast"]
      assert "ap-southeast" in Enum.map(Regions.selectable(), & &1.id)
    end
  end

  describe "private runner-cache regions" do
    test "the scaleway runner region is registered as private" do
      assert %Regions{provisioner_config: scw_config} = Regions.get("scw-fr-par-runners")
      assert scw_config.private == true
      assert scw_config.storage_class == "scw-local-nvme"
      assert scw_config.replicas == 1

      # No disk_envelope_size override: the ring derives from storage_size like
      # every managed region, so a per-account node here sizes its CAS ring the
      # same as its cross-region mesh peers and can stay caught up.
      assert scw_config.storage_size == "50Gi"
      assert scw_config.disk_envelope_size == nil
      assert scw_config.node_selector == %{"node.cluster.x-k8s.io/pool" => "kura-scw-fr-par"}
      refute Map.has_key?(scw_config, :public_host_template)
      refute Map.has_key?(scw_config, :ingress_class_name)

      # The retired Hetzner entry remains fetchable only so old resources can
      # be deleted. It is not an available serving region.
      assert Regions.all() |> Enum.filter(&Regions.private?/1) |> Enum.map(& &1.id) == [
               "scw-fr-par-runners",
               "hetzner-staging-runners"
             ]

      assert Regions.retired?(Regions.get("hetzner-staging-runners"))
      refute Regions.retired?(Regions.get("scw-fr-par-runners"))
    end
  end

  describe "private?/1" do
    test "is true only for private regions" do
      assert Regions.private?(Regions.get("scw-fr-par-runners"))
      refute Regions.private?(Regions.get("eu-central"))
      refute Regions.private?(Regions.get("local-controller"))
      refute Regions.private?(nil)
    end
  end

  describe "serves_runner_platform?/2" do
    test "scaleway region serves only the co-located macOS fleet" do
      scw = Regions.get("scw-fr-par-runners")

      assert scw.runner_platforms == [:macos]
      assert Regions.serves_runner_platform?(scw, :macos)
      refute Regions.serves_runner_platform?(scw, :linux)
    end

    test "no region serves the linux fleet" do
      # The Hetzner-backed staging region was the only :linux one, and it went
      # with its node pool. Linux runners fall back to the public endpoint.
      refute Enum.any?(Regions.all(), &Regions.serves_runner_platform?(&1, :linux))
    end

    test "scw region uses the node-port data plane; customer regions stay on cluster DNS" do
      assert Regions.node_port_data_plane?(Regions.get("scw-fr-par-runners"))
      refute Regions.node_port_data_plane?(Regions.get("eu-central"))
      refute Regions.node_port_data_plane?(nil)
    end

    test "public regions and nil serve no runner platform" do
      refute Regions.serves_runner_platform?(Regions.get("eu-central"), :linux)
      refute Regions.serves_runner_platform?(Regions.get("local-controller"), :macos)
      refute Regions.serves_runner_platform?(nil, :linux)
    end
  end

  describe "selectable/0" do
    test "excludes private regions a customer cannot pick" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)
      stub(Tuist.Environment, :kura_available_region_ids, fn -> ["eu-central", "scw-fr-par-runners"] end)

      available_ids = Enum.map(Regions.available(), & &1.id)
      selectable_ids = Enum.map(Regions.selectable(), & &1.id)

      assert "scw-fr-par-runners" in available_ids
      refute "scw-fr-par-runners" in selectable_ids
      assert "eu-central" in selectable_ids
    end
  end

  describe "available_region/1" do
    test "returns the region when it is available in the current runtime" do
      assert %Regions{id: "local-controller"} = Regions.available_region("local-controller")
    end

    test "returns nil for regions that are not available here" do
      assert Regions.available_region("local") == nil
      assert Regions.available_region("eu-central") == nil
    end
  end

  describe "available?/1" do
    test "is true only for regions available in the current runtime" do
      refute Regions.available?("local")
      assert Regions.available?("local-controller")
      refute Regions.available?("eu-central")
      refute Regions.available?(:local)
    end
  end

  describe "get/1" do
    test "returns the region for a known ID" do
      assert %Regions{id: "eu-central"} = Regions.get("eu-central")
    end

    test "returns nil for an unknown ID" do
      assert Regions.get("nonexistent") == nil
    end

    test "returns nil for a non-binary input" do
      assert Regions.get(:eu) == nil
      assert Regions.get(nil) == nil
    end
  end

  describe "fetch/1" do
    test "returns {:ok, region} when found" do
      assert {:ok, %Regions{id: "local-controller"}} = Regions.fetch("local-controller")
    end

    test "returns {:error, :not_found} for an unknown region" do
      assert Regions.fetch("nonexistent") == {:error, :not_found}
    end
  end

  describe "exists?/1" do
    test "true for registered, false otherwise" do
      assert Regions.exists?("eu-central")
      assert Regions.exists?("us-east")
      assert Regions.exists?("us-west")
      assert Regions.exists?("ap-southeast")
      assert Regions.exists?("local-controller")
      refute Regions.exists?("local")
      refute Regions.exists?("nope")
      refute Regions.exists?(nil)
      refute Regions.exists?(:eu)
    end
  end

  describe "local controller region with worktree scoping" do
    test "kind cluster + URL pick up TUIST_DEV_INSTANCE" do
      stub(Tuist.Environment, :dev_instance_suffix, fn -> 42 end)
      controller_region = Regions.get("local-controller")

      assert controller_region.provisioner_config.kubernetes_client[:context] ==
               "kind-kura-dev-42"

      assert controller_region.provisioner_config.public_url == "http://localhost:4142"
    end

    test "falls back to suffix 0 outside mise" do
      stub(Tuist.Environment, :dev_instance_suffix, fn -> 0 end)
      controller_region = Regions.get("local-controller")

      assert controller_region.provisioner_config.kubernetes_client[:context] == "kind-kura-dev-0"
      assert controller_region.provisioner_config.public_url == "http://localhost:4100"
    end
  end

  defp read_repo_yaml(path) do
    "../../../.."
    |> Path.expand(__DIR__)
    |> Path.join(path)
    |> File.read!()
    |> YamlElixir.read_from_string!()
  end

  defp production_node_pool_location(production_cluster, node_pool) do
    production_cluster
    |> get_in(["spec", "topology", "workers", "machineDeployments"])
    |> Enum.find_value(fn machine_deployment ->
      if get_in(machine_deployment, ["metadata", "labels", "node.cluster.x-k8s.io/pool"]) ==
           node_pool do
        machine_deployment["failureDomain"]
      end
    end)
  end

  describe "peer_public_host/2 and peer_public_url/2" do
    test "interpolate the account handle and cluster for a managed region" do
      region = Regions.get("eu-central")

      assert Regions.peer_public_host("Acme", region) == "peer.acme-eu-central-1.kura.tuist.dev"

      assert Regions.peer_public_url("Acme", region) ==
               "https://peer.acme-eu-central-1.kura.tuist.dev:7443"
    end

    test "return nil for regions without a peer public host (local controller)" do
      region = Regions.get("local-controller")

      assert Regions.peer_public_host("acme", region) == nil
      assert Regions.peer_public_url("acme", region) == nil
    end
  end
end
