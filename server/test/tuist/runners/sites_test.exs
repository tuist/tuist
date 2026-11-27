defmodule Tuist.Runners.SitesTest do
  use TuistTestSupport.Cases.DataCase, async: true

  import Mimic

  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.Sites

  setup :verify_on_exit!

  test "shard storage site comes only from the claiming node's operator label" do
    expect(Client, :get_node, fn "linux-node", _ ->
      {:ok,
       %{
         "metadata" => %{
           "labels" => %{
             "node.cluster.x-k8s.io/shard-storage-site" => "gra",
             "tuist.dev/private-network" => "pn-2024093"
           }
         }
       }}
    end)

    assert Sites.shard_storage_site("linux-node") == "gra"

    expect(Client, :get_node, fn "routes-pending", _ ->
      {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/shard-storage-site" => "gra"}}}}
    end)

    assert Sites.shard_storage_site("routes-pending") == nil
    expect(Client, :get_node, fn "unlabelled", _ -> {:ok, %{"metadata" => %{"labels" => %{}}}} end)
    assert Sites.shard_storage_site("unlabelled") == nil
    expect(Client, :get_node, fn "unreachable", _ -> {:error, :timeout} end)
    assert Sites.shard_storage_site("unreachable") == nil
    assert Sites.shard_storage_site(nil) == nil
  end

  test "an Actions cache host is a Linux node on its site's private network or a rack Mac at its site" do
    labels = fn labels -> {:ok, %{"metadata" => %{"labels" => labels}}} end

    expect(Client, :get_node, 4, fn
      "linux-node", _ ->
        labels.(%{"node.cluster.x-k8s.io/shard-storage-site" => "gra", "tuist.dev/private-network" => "pn-1"})

      "mac", _ ->
        labels.(%{"kubernetes.io/os" => "darwin", "node.cluster.x-k8s.io/rack-site" => "ber1"})

      "lent-mac", _ ->
        labels.(%{"kubernetes.io/os" => "darwin"})

      "linux-in-rack", _ ->
        labels.(%{"kubernetes.io/os" => "linux", "node.cluster.x-k8s.io/rack-site" => "ber1"})
    end)

    assert Sites.actions_cache_location("linux-node") == {:linux, "gra"}
    assert Sites.actions_cache_location("mac") == {:macos, "ber1"}
    assert Sites.actions_cache_location("lent-mac") == nil
    assert Sites.actions_cache_location("linux-in-rack") == nil
    assert Sites.actions_cache_location(nil) == nil
  end

  setup do
    prefix = Tuist.Environment.runners_macos_pool_name_prefix()
    site_pool = "#{prefix}-ber1-26-6"

    stub(Tuist.Environment, :runners_site_pools, fn ->
      %{site_pool => %{site: "ber1", platform: :macos}}
    end)

    cache = :"runners_sites_#{System.unique_integer([:positive])}"
    start_supervised!({Cachex, name: cache})
    stub(Sites, :cache_name, fn -> cache end)

    %{site_pool: site_pool}
  end

  describe "claim_site/2" do
    # The Node's site is cached by Node name, so each test reads its own Node.
    setup do
      %{node: "larch-runner-#{System.unique_integer([:positive])}"}
    end

    test "is the claiming Node's rack site", %{site_pool: site_pool, node: node} do
      expect(Client, :get_node, fn ^node, _opts ->
        {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/rack-site" => "larch"}}}}
      end)

      assert Sites.claim_site(site_pool, node) == "larch"
    end

    test "reads each Node once", %{site_pool: site_pool, node: node} do
      expect(Client, :get_node, 1, fn ^node, _opts ->
        {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/rack-site" => "larch"}}}}
      end)

      assert Sites.claim_site(site_pool, node) == "larch"
      assert Sites.claim_site(site_pool, node) == "larch"
    end

    test "is the pool's site for a Node without the label", %{site_pool: site_pool, node: node} do
      expect(Client, :get_node, fn ^node, _opts -> {:ok, %{"metadata" => %{"labels" => %{}}}} end)

      assert Sites.claim_site(site_pool, node) == "ber1"
    end

    test "is the pool's site while the Node cannot be read, and reads it again next time", %{
      site_pool: site_pool,
      node: node
    } do
      expect(Client, :get_node, fn ^node, _opts -> {:error, :timeout} end)

      assert Sites.claim_site(site_pool, node) == "ber1"

      expect(Client, :get_node, fn ^node, _opts ->
        {:ok, %{"metadata" => %{"labels" => %{"node.cluster.x-k8s.io/rack-site" => "larch"}}}}
      end)

      assert Sites.claim_site(site_pool, node) == "larch"
    end

    test "is the pool's site when the Pod's Node is unknown", %{site_pool: site_pool} do
      reject(&Client.get_node/2)

      assert Sites.claim_site(site_pool, nil) == "ber1"
    end

    test "is nil off the rack without reading the Node" do
      reject(&Client.get_node/2)

      assert Sites.claim_site("tuist-runner-pool-linux-4vcpu-16gb", "linux-node-1") == nil
    end
  end
end
