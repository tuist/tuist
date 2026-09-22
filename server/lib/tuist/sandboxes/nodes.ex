defmodule Tuist.Sandboxes.Nodes do
  @moduledoc """
  Cluster-wide view of the connected sandboxd nodes and the
  request/response bridge onto their WebSocket processes.

  Each `TuistWeb.SandboxNodeWebSock` tracks itself in
  `Tuist.Sandboxes.NodePresence` under its node name on `hello`, keeps
  the meta (capacity, templates, sandboxes) fresh from `report` frames
  and subscribes to the node's command topic. `call/4` broadcasts a
  command on that topic from whichever replica the caller runs on and
  blocks the caller until the node's `result` frame arrives, relaying
  `stream` frames to an optional callback in between. Presences
  disappear with the socket process, so a node is "connected" exactly
  while its socket is alive somewhere in the cluster.

  Callers inside the application always use `call/4` with an explicit
  options list, so the call can be intercepted as one function in tests.
  """

  alias Phoenix.PubSub
  alias Tuist.Sandboxes.NodePresence

  @pubsub Tuist.PubSub
  @presence_topic "sandbox_nodes"
  @default_timeout to_timeout(minute: 1)
  @long_timeout to_timeout(second: 120)

  def presence_topic, do: @presence_topic

  def topic(node_name) when is_binary(node_name), do: "sandbox_node:" <> node_name

  @doc """
  Runs on the socket process: subscribes it to the node's command topic,
  tells any older socket for the same node name to close and tracks the
  socket's presence with `info` plus its pid, Erlang node and connection
  time.
  """
  def track(node_name, info) when is_binary(node_name) and is_map(info) do
    :ok = PubSub.subscribe(@pubsub, topic(node_name))
    :ok = PubSub.broadcast_from(@pubsub, self(), topic(node_name), :sandbox_node_superseded)
    meta = Map.merge(info, %{pid: self(), node: node(), connected_at: DateTime.utc_now()})

    case NodePresence.track(self(), @presence_topic, node_name, meta) do
      {:ok, _ref} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def update(node_name, info) when is_binary(node_name) and is_map(info) do
    case NodePresence.update(self(), @presence_topic, node_name, &Map.merge(&1, info)) do
      {:ok, _ref} -> :ok
      {:error, _reason} -> {:error, :not_connected}
    end
  end

  def untrack(node_name) when is_binary(node_name) do
    :ok = NodePresence.untrack(self(), @presence_topic, node_name)
    PubSub.unsubscribe(@pubsub, topic(node_name))
  end

  def lookup(node_name) when is_binary(node_name) do
    case NodePresence.get_by_key(@presence_topic, node_name) do
      %{metas: [_ | _] = metas} ->
        %{pid: pid} = meta = latest(metas)
        {:ok, pid, info(meta)}

      _none ->
        {:error, :not_connected}
    end
  end

  def lookup(_node_name), do: {:error, :not_connected}

  def connected?(node_name) do
    match?({:ok, _pid, _info}, lookup(node_name))
  end

  def connected_nodes do
    @presence_topic
    |> NodePresence.list()
    |> Enum.map(fn {name, %{metas: metas}} -> metas |> latest() |> info() |> Map.put(:name, name) end)
    |> Enum.sort_by(& &1.name)
  end

  # A node reconnecting before its previous socket is gone has two
  # presences for a moment; the newest connection is the live one.
  defp latest(metas), do: Enum.max_by(metas, & &1.connected_at, DateTime)

  defp info(meta), do: Map.drop(meta, [:phx_ref, :phx_ref_prev])

  @doc """
  Picks the node a sandbox should run on. A sandbox that already lives
  on a node must stay there (its jail directory is local), so that node
  wins when it is connected. A new sandbox goes to the least loaded
  connected node that reports its template ready.
  """
  def node_with_capacity(opts) do
    node_name = Map.get(opts, :node_name)
    template = Map.get(opts, :template)

    cond do
      is_binary(node_name) and connected?(node_name) ->
        {:ok, node_name}

      is_binary(node_name) ->
        {:error, :not_connected}

      true ->
        connected_nodes()
        |> Enum.filter(&template_ready?(&1, template))
        |> Enum.sort_by(&length(Map.get(&1, :sandboxes, [])))
        |> case do
          [node | _] -> {:ok, node.name}
          [] -> {:error, :no_node}
        end
    end
  end

  defp template_ready?(node, template) do
    node
    |> Map.get(:templates, [])
    |> Enum.any?(fn candidate -> candidate.name == template and candidate.ready end)
  end

  @doc """
  Sends `op` with `args` to the node and waits for its result. The
  command is broadcast on the node's topic, so it reaches the socket on
  whichever replica holds it; the socket process is monitored so a
  socket that dies mid-call answers `{:error, :node_disconnected}`.

  Options:

    * `:timeout` in milliseconds; defaults to 120s for `create`/`resume`
      and 60s otherwise.
    * `:on_stream` a one-arity function receiving `{:stdout | :stderr,
      binary}` for every stream frame the node emits before the result.
  """
  def call(node_name, op, args, opts) when is_map(args) and is_list(opts) do
    timeout = Keyword.get(opts, :timeout, default_timeout(op))
    on_stream = Keyword.get(opts, :on_stream)

    with {:ok, pid, _info} <- lookup(node_name) do
      ref = make_ref()
      monitor = Process.monitor(pid)
      :ok = PubSub.broadcast(@pubsub, topic(node_name), {:sandbox_command, ref, to_string(op), args, self()})
      deadline = System.monotonic_time(:millisecond) + timeout
      await(ref, monitor, deadline, on_stream)
    end
  end

  defp await(ref, monitor, deadline, on_stream) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:sandbox_stream, ^ref, stream, data} ->
        if is_function(on_stream, 1), do: on_stream.({stream, data})
        await(ref, monitor, deadline, on_stream)

      {:sandbox_result, ^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _pid, _reason} ->
        {:error, :node_disconnected}
    after
      remaining ->
        Process.demonitor(monitor, [:flush])
        {:error, :timeout}
    end
  end

  defp default_timeout(op) when op in ["create", "resume", :create, :resume], do: @long_timeout
  defp default_timeout(_op), do: @default_timeout
end
