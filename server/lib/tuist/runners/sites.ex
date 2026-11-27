defmodule Tuist.Runners.Sites do
  @moduledoc """
  Where rack runners are.

  A rack pool spans every site whose runners are on, so a queued job is bound
  to its Xcode and shape, not to a site: the Node of the runner that claims it
  decides the site (`claim_site/2`). A runner takes the oldest job it can,
  whichever site holds its account's runner cache.
  """

  alias Tuist.KeyValueStore
  alias Tuist.Kubernetes.Client
  alias Tuist.Runners.Catalog

  require Logger

  @site_label "node.cluster.x-k8s.io/rack-site"
  @read_timeout to_timeout(second: 5)
  @node_site_ttl_ms to_timeout(minute: 10)

  def cache_name, do: :tuist

  @doc """
  The site a runner of `fleet_name` on `node_name` claims at: the Node's
  `node.cluster.x-k8s.io/rack-site` label, else the pool's site
  (`Catalog.fleet_site/1`), which is also the answer while the Node cannot be
  read. A host lent to another env registers in that env's cluster without the
  label. `nil` for a pool that is not racked at a site, without reading the
  Node.
  """
  def claim_site(fleet_name, node_name) do
    case Catalog.fleet_site(fleet_name) do
      nil -> nil
      pool_site -> node_site(node_name) || pool_site
    end
  end

  @doc """
  The storage site of the actual claiming Linux node. The provider sets
  `tuist.dev/private-network` only once every peer has its private routes.
  """
  def shard_storage_site(node_name) when is_binary(node_name) and node_name != "" do
    case Client.get_node(node_name, timeout: @read_timeout) do
      {:ok, node} -> node |> get_in(["metadata", "labels"]) |> attested_storage_site()
      _ -> nil
    end
  end

  def shard_storage_site(_), do: nil

  @doc """
  Where the GitHub Actions cache host `node_name` reaches stores from:
  `{:linux, site}` for a Linux node on its site's private network
  (`shard_storage_site/1`), `{:macos, site}` for a rack Mac, which reaches a
  store only through its rack site's gateway entrance, else `nil`. Both labels
  come from the provider, never from the host.
  """
  def actions_cache_location(node_name) when is_binary(node_name) and node_name != "" do
    with {:ok, node} <- Client.get_node(node_name, timeout: @read_timeout),
         labels when is_map(labels) <- get_in(node, ["metadata", "labels"]) do
      case {attested_storage_site(labels), labels} do
        {site, _} when is_binary(site) ->
          {:linux, site}

        {nil, %{"kubernetes.io/os" => "darwin", @site_label => site}} when is_binary(site) and site != "" ->
          {:macos, site}

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  def actions_cache_location(_), do: nil

  defp attested_storage_site(%{
         "node.cluster.x-k8s.io/shard-storage-site" => site,
         "tuist.dev/private-network" => network
       })
       when is_binary(site) and site != "" and is_binary(network) and network != "", do: site

  defp attested_storage_site(_), do: nil

  @doc """
  The `node.cluster.x-k8s.io/rack-site` label of the Node named `node_name`, or
  `nil` when it has none or cannot be read. Cached per Node.
  """
  def node_site(node_name) when is_binary(node_name) and node_name != "" do
    [__MODULE__, :node_site, node_name]
    |> KeyValueStore.get_or_update([cache: cache_name(), ttl: @node_site_ttl_ms, cache_errors: false], fn ->
      case Client.get_node(node_name, timeout: @read_timeout) do
        {:ok, node} -> {:ok, get_in(node, ["metadata", "labels", @site_label])}
        other -> {:error, other}
      end
    end)
    |> case do
      {:ok, site} when is_binary(site) and site != "" ->
        site

      {:ok, _no_label} ->
        nil

      {:error, reason} ->
        Logger.warning("runners: could not read a Node's site",
          node: node_name,
          reason: inspect(reason)
        )

        nil
    end
  end

  def node_site(_node_name), do: nil
end
