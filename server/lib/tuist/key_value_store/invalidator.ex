defmodule Tuist.KeyValueStore.Invalidator do
  @moduledoc """
  Evicts local display-cache entries after mutations on another web node.

  Membership changes clear only the dedicated display cache to recover from
  missed invalidations, never the general request/integration or license caches.
  Lost messages and fills racing an invalidation can still leave display values
  stale until their TTL. Authentication and authorization do not depend on this
  eventual invalidation mechanism.
  """

  use GenServer

  alias FunWithFlags.Store.Cache

  @topic "key_value_store:invalidations"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def broadcast(key) do
    case Process.whereis(__MODULE__) do
      nil -> Phoenix.PubSub.broadcast(Tuist.PubSub, @topic, {:invalidate_cache_key, key})
      pid -> Phoenix.PubSub.broadcast_from(Tuist.PubSub, pid, @topic, {:invalidate_cache_key, key})
    end
  end

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(Tuist.PubSub, @topic)
    :net_kernel.monitor_nodes(true)
    {:ok, Keyword.get(opts, :cache, :display)}
  end

  @impl true
  def handle_info({:invalidate_cache_key, key}, cache) do
    Cachex.del(cache, key)
    {:noreply, cache}
  end

  def handle_info({event, _node}, cache) when event in [:nodeup, :nodedown] do
    Cachex.clear(cache)
    Cache.flush()
    {:noreply, cache}
  end
end
