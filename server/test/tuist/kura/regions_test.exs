defmodule Tuist.Kura.RegionsTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.Provider.HelmKubernetes
  alias Tuist.Kura.Regions

  describe "all/0" do
    test "exposes the eu production region backed by HelmKubernetes" do
      assert %Regions{id: "eu", provider: HelmKubernetes, provider_config: config} =
               Enum.find(Regions.all(), &(&1.id == "eu"))

      assert config.cluster_id == "eu-1"
      assert config.helm_overlay == "hetzner"
    end

    test "exposes the local dev region backed by HelmKubernetes" do
      assert %Regions{id: "local", provider: HelmKubernetes, provider_config: config} =
               Enum.find(Regions.all(), &(&1.id == "local"))

      assert config.helm_overlay == "local"
      assert config.kind_cluster_name == "kura-dev"
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

  describe "HelmKubernetes.public_url/3" do
    test "interpolates the production host template with the account handle" do
      region = Regions.get("eu")
      assert HelmKubernetes.public_url("tuist", region, "any-ref") == "https://tuist-eu-1.kura.tuist.dev"
    end

    test "uses the literal local URL for kind-backed regions" do
      region = Regions.get("local")
      assert HelmKubernetes.public_url("tuist", region, "any-ref") == "http://localhost:4000"
    end
  end

  describe "HelmKubernetes.release_name/2" do
    test "produces a kura-<account>-<cluster> release name" do
      region = Regions.get("eu")
      assert HelmKubernetes.release_name("tuist", region) == "kura-tuist-eu-1"
    end

    test "uses the local cluster_id for kind regions" do
      region = Regions.get("local")
      assert HelmKubernetes.release_name("tuist", region) == "kura-tuist-local"
    end
  end
end
