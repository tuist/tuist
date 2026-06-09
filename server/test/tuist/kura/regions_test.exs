defmodule Tuist.Kura.RegionsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions

  setup :set_mimic_from_context

  describe "all/0" do
    test "exposes concrete managed regions backed by KubernetesController" do
      ids = Enum.map(Regions.all(), & &1.id)
      hetzner_locations = %{"eu-central" => "fsn1", "us-east" => "ash", "us-west" => "hil"}

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
        assert config.hetzner_location == hetzner_locations[id]
        assert config.ingress_class_name == ingress_classes[id]
        assert config.storage_class == "hcloud-volumes"
      end

      assert Regions.get("us-east").provisioner_config.node_selector == %{
               "node.cluster.x-k8s.io/pool" => "kura-us-east"
             }

      assert Regions.get("us-west").provisioner_config.node_selector == %{
               "node.cluster.x-k8s.io/pool" => "kura-us-west"
             }

      assert Regions.get("eu-central").provisioner_config.node_selector == %{
               "node.cluster.x-k8s.io/pool" => "kura"
             }

      for id <- ["us-east", "us-west", "eu-central"] do
        refute Map.has_key?(Regions.get(id).provisioner_config, :kubernetes_client)
        refute Map.has_key?(Regions.get(id).provisioner_config, :peer_tls_secret_name)
      end
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

    test "reads the managed-region Tuist base URL from the environment adapter" do
      stub(Tuist.Environment, :kura_tuist_base_url, fn ->
        "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"
      end)

      assert Regions.get("eu-central").provisioner_config.tuist_base_url ==
               "http://tuist-tuist-server.tuist-canary.svc.cluster.local:80"
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
end
