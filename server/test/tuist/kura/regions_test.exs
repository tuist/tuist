defmodule Tuist.Kura.RegionsTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Tuist.Kura.Provisioner.HelmKubernetes
  alias Tuist.Kura.Provisioner.HetznerCloud
  alias Tuist.Kura.Regions

  setup :set_mimic_from_context

  describe "all/0" do
    test "exposes the eu production region backed by HetznerCloud" do
      assert %Regions{id: "eu", provisioner: HetznerCloud, provisioner_config: config} =
               Enum.find(Regions.all(), &(&1.id == "eu"))

      assert config.location == "fsn1"
      assert config.target_id == "fsn1"
    end

    test "exposes the local dev region backed by HelmKubernetes" do
      assert %Regions{id: "local", provisioner: HelmKubernetes, provisioner_config: config} =
               Enum.find(Regions.all(), &(&1.id == "local"))

      assert config.helm_overlay == "local"
    end
  end

  describe "available/0" do
    test "returns only the local region in test" do
      assert Enum.map(Regions.available(), & &1.id) == ["local"]
    end
  end

  describe "available_region/1" do
    test "returns the region when it is available in the current runtime" do
      assert %Regions{id: "local"} = Regions.available_region("local")
    end

    test "returns nil for a registered region that is not available here" do
      assert Regions.available_region("eu") == nil
    end
  end

  describe "available?/1" do
    test "is true only for regions available in the current runtime" do
      assert Regions.available?("local")
      refute Regions.available?("eu")
      refute Regions.available?(:local)
    end
  end

  describe "get/1" do
    test "returns the region for a known ID" do
      assert %Regions{id: "eu"} = Regions.get("eu")
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
      assert {:ok, %Regions{id: "local"}} = Regions.fetch("local")
    end

    test "returns {:error, :not_found} for an unknown region" do
      assert Regions.fetch("nonexistent") == {:error, :not_found}
    end
  end

  describe "exists?/1" do
    test "true for registered, false otherwise" do
      assert Regions.exists?("eu")
      assert Regions.exists?("local")
      refute Regions.exists?("nope")
      refute Regions.exists?(nil)
      refute Regions.exists?(:eu)
    end
  end

  describe "local region with worktree scoping" do
    test "kind cluster + URL pick up TUIST_DEV_INSTANCE" do
      stub(Tuist.Environment, :dev_instance_suffix, fn -> 42 end)
      region = Regions.get("local")

      assert region.provisioner_config.kind_cluster_name == "kura-dev-42"
      assert region.provisioner_config.public_url == "http://localhost:4042"
    end

    test "falls back to suffix 0 outside mise" do
      stub(Tuist.Environment, :dev_instance_suffix, fn -> 0 end)
      region = Regions.get("local")

      assert region.provisioner_config.kind_cluster_name == "kura-dev-0"
      assert region.provisioner_config.public_url == "http://localhost:4000"
    end
  end
end
