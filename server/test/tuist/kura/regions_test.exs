defmodule Tuist.Kura.RegionsTest do
  # Mutates TUIST_DEV_INSTANCE around the local-region tests, so we
  # can't run async with anything else that reads it.
  use ExUnit.Case, async: false

  alias Tuist.Kura.Deployer.HelmKubernetes
  alias Tuist.Kura.Regions

  setup do
    previous = System.get_env("TUIST_DEV_INSTANCE")
    on_exit(fn -> reset_env("TUIST_DEV_INSTANCE", previous) end)
    :ok
  end

  describe "all/0" do
    test "exposes the eu production region backed by HelmKubernetes" do
      assert %Regions{id: "eu", deployer: HelmKubernetes, deployer_config: config} =
               Enum.find(Regions.all(), &(&1.id == "eu"))

      assert config.cluster_id == "eu-1"
      assert config.helm_overlay == "hetzner"
    end

    test "exposes the local dev region backed by HelmKubernetes" do
      assert %Regions{id: "local", deployer: HelmKubernetes, deployer_config: config} =
               Enum.find(Regions.all(), &(&1.id == "local"))

      assert config.helm_overlay == "local"
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
      System.put_env("TUIST_DEV_INSTANCE", "42")
      region = Regions.get("local")

      assert region.deployer_config.kind_cluster_name == "kura-dev-42"
      assert region.deployer_config.public_url == "http://localhost:4042"
      assert HelmKubernetes.public_url("tuist", region, "any-ref") == "http://localhost:4042"
    end

    test "falls back to suffix 0 outside mise" do
      System.delete_env("TUIST_DEV_INSTANCE")
      region = Regions.get("local")

      assert region.deployer_config.kind_cluster_name == "kura-dev-0"
      assert region.deployer_config.public_url == "http://localhost:4000"
    end
  end

  describe "HelmKubernetes.public_url/3 (eu)" do
    test "interpolates the production host template with the account handle" do
      region = Regions.get("eu")
      assert HelmKubernetes.public_url("tuist", region, "any-ref") == "https://tuist-eu-1.kura.tuist.dev"
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

  defp reset_env(name, nil), do: System.delete_env(name)
  defp reset_env(name, value), do: System.put_env(name, value)
end
