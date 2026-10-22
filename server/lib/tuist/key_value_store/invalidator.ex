defmodule Tuist.KeyValueStore.Invalidator do
  @moduledoc """
  Evicts local display-cache entries after mutations on another web node.

  Membership changes clear the entire selected cache to recover from missed
  invalidations. A flapping node can therefore cause extra database reads on
  every surviving node until their caches warm again. Authentication and
  authorization do not depend on this eventual invalidation mechanism.
  """

  use GenServer

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
    {:ok, Keyword.get(opts, :cache, :tuist)}
  end

  @impl true
  def handle_info({:invalidate_cache_key, key}, cache) do
    Cachex.del(cache, key)
    {:noreply, cache}
  end

  def handle_info({event, _node}, cache) when event in [:nodeup, :nodedown] do
    Cachex.clear(cache)
    FunWithFlags.Store.Cache.flush()
    {:noreply, cache}
  end
end
