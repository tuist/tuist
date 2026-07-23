defmodule TuistWeb.RateLimit.InMemory do
  @moduledoc """
  Distributed, eventually consistent rate limiter using `Phoenix.PubSub` and `Hammer`.

  This module provides a rate-limiting mechanism for requests using a distributed,
  eventually consistent approach. It combines local in-memory counting with a
  broadcasting mechanism to keep counters in sync across nodes in a cluster.
  """
  defmodule Local do
    @moduledoc false
    use Hammer, backend: :ets
    # This inner module handles local hit counting via Hammer with ETS as a backend.
  end

  defmodule TokenBucket do
    @moduledoc false
    use Hammer, backend: :ets, algorithm: :token_bucket
  end

  # Checks rate locally and broadcasts the hit to other nodes to synchronize.
  def hit(key, scale, limit, increment \\ 1) do
    :ok = broadcast({:fixed_window, key, scale, increment})
    Local.hit(key, scale, limit, increment)
  end

  def hit_token_bucket(key, refill_rate, capacity, cost \\ 1) do
    :ok = broadcast({:token_bucket, key, refill_rate, capacity, cost})
    TokenBucket.hit(key, refill_rate, capacity, cost)
  end

  defmodule Listener do
    @moduledoc false
    use GenServer

    # Starts the listener process, subscribing to the specified PubSub topic.
    # This process will listen for hit messages to keep local counters in sync.

    @doc false
    def start_link(opts) do
      pubsub = Keyword.fetch!(opts, :pubsub)
      topic = Keyword.fetch!(opts, :topic)
      GenServer.start_link(__MODULE__, {pubsub, topic}, name: __MODULE__)
    end

    @impl true
    def init({pubsub, topic}) do
      :ok = Phoenix.PubSub.subscribe(pubsub, topic)
      {:ok, []}
    end

    # Handles remote hit messages by updating the local limiter.

    @impl true
    def handle_info({:fixed_window, key, scale, increment}, state) do
      _count = Local.inc(key, scale, increment)
      {:noreply, state}
    end

    @impl true
    def handle_info({:token_bucket, key, refill_rate, capacity, cost}, state) do
      _result = TokenBucket.hit(key, refill_rate, capacity, cost)
      {:noreply, state}
    end
  end

  @pubsub Tuist.PubSub
  @topic "__ratelimit"

  # Sends a message to other nodes in the cluster to synchronize rate-limiting information.
  defp broadcast(message) do
    listener = Process.whereis(Listener)
    Phoenix.PubSub.broadcast_from(@pubsub, listener, @topic, message)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  # Wraps the local Hammer counter and the listener processes under a single supervisor.
  def start_link(opts) do
    children = [{Local, opts}, {TokenBucket, opts}, {Listener, pubsub: @pubsub, topic: @topic}]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
