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
        assert config.storage_size == "50Gi"
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
      for id <- ["us-east", "us-west", "eu-central", "ca-east"] do
        assert Regions.get(id).provisioner_config.egress_guaranteed_mbps == 25
      end

      # The burst ceiling stays per-box and rides the pod annotation.
      assert Regions.get("us-east").provisioner_config.pod_annotations == %{
               "kubernetes.io/egress-bandwidth" => "1500M"
             }
    end

    test "runs eu-central on Dedibox bare metal" do
      config = Regions.get("eu-central").provisioner_config

      assert config.node_selector == %{"node.cluster.x-k8s.io/pool" => "kura-dedibox"}
      assert config.storage_class == "scw-local-nvme"
      assert config.gateway == :host_network
      assert config.replicas == 2
      assert config.storage_size == "50Gi"
      assert config.hetzner_location == nil

      # Identity is unchanged so the cutover is invisible to the customer and CLI.
      assert config.cluster_id == "eu-central-1"
      assert config.ingress_class_name == "kura-eu-central"
      assert Regions.get("eu-central").display_name == "EU Central"
    end

    test "enables the per-account peer mesh on managed and private regions" do
      for id <- ["us-east", "us-west", "eu-central", "scw-fr-par-runners", "hetzner-staging-runners"] do
        assert Regions.get(id).provisioner_config.mesh == true,
               "expected region #{id} to enable the peer mesh"
      end
    end

    test "tolerates the runner-cache node taint only on the scaleway runner-cache region" do
      assert Regions.get("scw-fr-par-runners").provisioner_config.tolerations == [
               %{"key" => "tuist.dev/runner-cache", "operator" => "Exists", "effect" => "NoSchedule"}
             ]

      # The Hetzner runner-cache pool isn't tainted, so its region carries no toleration.
      assert Regions.get("hetzner-staging-runners").provisioner_config.tolerations == []
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
  end

  describe "private runner-cache regions" do
    test "scaleway and hetzner-staging runner regions are registered as private" do
      assert %Regions{provisioner_config: scw_config} = Regions.get("scw-fr-par-runners")
      assert scw_config.private == true
      assert scw_config.storage_class == "scw-local-nvme"
      assert scw_config.replicas == 1
      assert scw_config.node_selector == %{"node.cluster.x-k8s.io/pool" => "kura-scw-fr-par"}
      refute Map.has_key?(scw_config, :public_host_template)
      refute Map.has_key?(scw_config, :ingress_class_name)

      assert %Regions{provisioner_config: hetzner_config} = Regions.get("hetzner-staging-runners")
      assert hetzner_config.private == true
      assert hetzner_config.storage_class == "hcloud-volumes"
      assert hetzner_config.replicas == 1
      assert hetzner_config.node_selector == %{"node.cluster.x-k8s.io/pool" => "kura"}
    end
  end

  describe "private?/1" do
    test "is true only for private regions" do
      assert Regions.private?(Regions.get("scw-fr-par-runners"))
      assert Regions.private?(Regions.get("hetzner-staging-runners"))
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

    test "staging hetzner region serves only the co-located linux fleet" do
      staging = Regions.get("hetzner-staging-runners")

      assert staging.runner_platforms == [:linux]
      assert Regions.serves_runner_platform?(staging, :linux)
      refute Regions.serves_runner_platform?(staging, :macos)
    end

    test "scw region uses the node-port data plane; hetzner stays on cluster DNS" do
      assert Regions.node_port_data_plane?(Regions.get("scw-fr-par-runners"))
      refute Regions.node_port_data_plane?(Regions.get("hetzner-staging-runners"))
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
      stub(Tuist.Environment, :kura_available_region_ids, fn -> ["eu-central", "hetzner-staging-runners"] end)

      available_ids = Enum.map(Regions.available(), & &1.id)
      selectable_ids = Enum.map(Regions.selectable(), & &1.id)

      assert "hetzner-staging-runners" in available_ids
      refute "hetzner-staging-runners" in selectable_ids
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
