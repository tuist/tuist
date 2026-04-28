defmodule Tuist.Kura.ClustersTest do
  use ExUnit.Case, async: true

  alias Tuist.Kura.Clusters

  describe "all/0" do
    test "exposes the eu-1 production cluster" do
      assert %Clusters{id: "eu-1", region: "eu", provider: "hetzner"} =
               Enum.find(Clusters.all(), &(&1.id == "eu-1"))
    end

    test "exposes the local-1 dev cluster" do
      assert %Clusters{id: "local-1", region: "local", provider: "local"} =
               Enum.find(Clusters.all(), &(&1.id == "local-1"))
    end
  end

  describe "get/1" do
    test "returns the cluster for a known ID" do
      assert %Clusters{id: "eu-1"} = Clusters.get("eu-1")
    end

    test "returns nil for an unknown ID" do
      assert Clusters.get("nonexistent") == nil
    end
  end

  describe "exists?/1" do
    test "true for registered, false otherwise" do
      assert Clusters.exists?("eu-1")
      refute Clusters.exists?("nope")
    end
  end

  describe "public_url/2" do
    test "joins the account handle and the cluster ID under kura.tuist.dev" do
      cluster = Clusters.get("eu-1")
      assert Clusters.public_url("tuist", cluster) == "https://tuist-eu-1.kura.tuist.dev"
    end
  end

  describe "release_name/2" do
    test "produces a kura-<account>-<cluster> release name" do
      cluster = Clusters.get("eu-1")
      assert Clusters.release_name("tuist", cluster) == "kura-tuist-eu-1"
    end
  end
end
