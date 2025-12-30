defmodule TuistWeb.RateLimit.InMemory do
  @moduledoc """
  Distributed, eventually consistent rate limiter using `Phoenix.PubSub` and `Hammer`.

  This module provides a rate-limiting mechanism for requests using a distributed,
  eventually consistent approach. It combines local in-memory counting with a
  broadcasting mechanism to keep counters in sync across nodes in a cluster.
  """
  alias Tuist.Environment

  defmodule Local do
    @moduledoc false
    use Hammer, backend: :ets
    # This inner module handles local hit counting via Hammer with ETS as a backend.
  end

  # Checks rate locally and broadcasts the hit to other nodes to synchronize.
  def hit(key, scale, limit, increment \\ 1) do
    :ok = broadcast({:inc, key, scale, increment})
    Local.hit(key, scale, limit, increment)
  end

  defmodule Listener do
    @moduledoc false
    use GenServer

    # Starts the listener process, subscribing to the specified PubSub topic.
    # This process will listen for `:inc` messages to keep local counters in sync.

    @doc false
    def start_link(opts) do
      pubsub = Keyword.fetch!(opts, :pubsub)
      topic = Keyword.fetch!(opts, :topic)
      GenServer.start_link(__MODULE__, {pubsub, topic})
    end

    @impl true
    def init({pubsub, topic}) do
      :ok = Phoenix.PubSub.subscribe(pubsub, topic)
      {:ok, []}
    end

    # Handles remote `:inc` messages by updating the local counter.

    @impl true
    def handle_info({:inc, key, scale, increment}, state) do
      _count = Local.inc(key, scale, increment)
      {:noreply, state}
    end
  end

  def rate_limit(%Plug.Conn{} = conn, _opts) do
    if Environment.tuist_hosted?() do
      scale_ms = to_timeout(minute: 1)
      limit = 1_000

      case hit(TuistWeb.RemoteIp.get(conn), scale_ms, limit) do
        {:allow, _count} ->
          conn

        {:deny, _limit} ->
          raise TuistWeb.Errors.TooManyRequestsError,
            message: "You have made too many requests. Please try again later."
      end
    else
      conn
    end
  end

  @pubsub Tuist.PubSub
  @topic "__ratelimit"

  # Sends a message to other nodes in the cluster to synchronize rate-limiting information.
  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, message)
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
    children = [{Local, opts}, {Listener, pubsub: @pubsub, topic: @topic}]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
