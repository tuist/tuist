defmodule Tuist.Runners.VolumePrefetchTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.VolumePrefetch

  setup :verify_on_exit!

  @fleet "tuist-tuist-runners-fleet"

  setup do
    stub(K8sClient, :list_runner_pools, fn _namespace ->
      {:ok,
       [
         runner_pool("macos-26-6", @fleet),
         runner_pool("linux-4vcpu-16gb", "runners-linux")
       ]}
    end)

    :ok
  end

  defp runner_pool(name, fleet_selector) do
    %{"metadata" => %{"name" => name}, "spec" => %{"fleetSelector" => fleet_selector}}
  end

  @m2 %{"cpu" => "8", "memory" => "14Gi"}
  @m4 %{"cpu" => "12", "memory" => "28Gi"}

  defp fleet_node(name, fleet \\ @fleet, capacity \\ @m2) do
    %{"metadata" => %{"name" => name, "labels" => %{"tuist.dev/fleet" => fleet}}, "status" => %{"capacity" => capacity}}
  end

  defp stub_fleet(nodes) do
    stub(K8sClient, :get_node, fn name ->
      case Enum.find(nodes, &(get_in(&1, ["metadata", "name"]) == name)) do
        nil -> {:error, :not_found}
        node -> {:ok, node}
      end
    end)

    stub(K8sClient, :list_nodes, fn "tuist.dev/fleet=" <> _ -> {:ok, %{"items" => nodes}} end)
  end

  describe "node_for_service_account/2" do
    test "names the Node of a host's own ServiceAccount" do
      assert VolumePrefetch.node_for_service_account("tuist", "tart-kubelet-mac-01") == {:ok, "mac-01"}
    end

    test "refuses any other ServiceAccount" do
      assert VolumePrefetch.node_for_service_account("tuist-runners", "tart-kubelet-mac-01") == :error
      assert VolumePrefetch.node_for_service_account("tuist", "tuist-runners-controller") == :error
      assert VolumePrefetch.node_for_service_account("tuist", "tart-kubelet-") == :error
    end
  end

  describe "for_node/2" do
    test "lists the saved custom volumes jobs used on the host class to every Node of it" do
      custom = %{
        kind: "custom",
        id: "11111111-1111-4111-8111-111111111111",
        account_id: 1,
        scope: String.duplicate("s", 64),
        generation: 2,
        image_digest: String.duplicate("a", 40),
        content_digest: String.duplicate("c", 64),
        reason: "prewarm"
      }

      stub_fleet([fleet_node("mac-01"), fleet_node("mac-02"), fleet_node("m4-01", @fleet, @m4)])

      expect(CacheVolumes, :prefetch_heads, 2, fn "macos", nodes, %DateTime{} ->
        assert Enum.sort(nodes) == ["mac-01", "mac-02"]
        [custom]
      end)

      assert VolumePrefetch.for_node("mac-01", :macos) == [custom]
      assert VolumePrefetch.for_node("mac-02", :macos) == [custom]
    end

    test "lists a Linux fleet's HEADs to every Node of it, whatever its capacity" do
      stub_fleet([fleet_node("linux-01", "runners-linux"), fleet_node("linux-02", "runners-linux", @m4)])

      expect(CacheVolumes, :prefetch_heads, fn "linux", nodes, %DateTime{} ->
        assert Enum.sort(nodes) == ["linux-01", "linux-02"]
        []
      end)

      assert VolumePrefetch.for_node("linux-01", :linux) == []
    end

    test "answers nothing for a Node outside a fleet of the platform" do
      stub_fleet([fleet_node("linux-01", "runners-linux"), fleet_node("mac-01")])
      reject(&CacheVolumes.prefetch_heads/3)

      assert VolumePrefetch.for_node("linux-01", :macos) == []
      assert VolumePrefetch.for_node("mac-01", :linux) == []
    end

    test "answers nothing for a Node it cannot read" do
      stub(K8sClient, :get_node, fn "mac-01" -> {:error, :not_found} end)

      assert VolumePrefetch.for_node("mac-01", :macos) == []
    end
  end
end
