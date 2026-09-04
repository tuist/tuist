defmodule Tuist.Sandboxes.Nodes do
  @moduledoc """
  Registry of connected sandboxd nodes and the request/response bridge
  onto their WebSocket processes.

  Each `TuistWeb.SandboxNodeWebSock` registers itself under its node name
  on `hello` and keeps the value (capacity, templates, sandboxes) fresh
  from `report` frames. `call/4` sends a command to the socket process and
  blocks the caller until the node's `result` frame arrives, relaying
  `stream` frames to an optional callback in between. Registry entries
  disappear with the socket process, so a node is "connected" exactly
  while its socket is alive.

  Callers inside the application always use `call/4` with an explicit
  options list, so the call can be intercepted as one function in tests.
  """

  @registry __MODULE__
  @default_timeout to_timeout(minute: 1)
  @long_timeout to_timeout(second: 120)
  @supersede_timeout to_timeout(second: 5)
  @supersede_poll_ms 50

  def child_spec(_opts) do
    Registry.child_spec(keys: :unique, name: @registry)
  end

  def register(node_name, info) when is_binary(node_name) and is_map(info) do
    register(node_name, info, 1)
  end

  defp register(node_name, info, retries) do
    case Registry.register(@registry, node_name, info) do
      {:ok, _owner} ->
        :ok

      {:error, {:already_registered, pid}} when retries > 0 ->
        supersede(node_name, pid)
        register(node_name, info, retries - 1)

      {:error, {:already_registered, _pid}} ->
        {:error, :already_registered}
    end
  end

  # A reconnect from the same node is a fresh hello: the previous socket
  # is told to close and waited on until it exits or gives the name up,
  # then killed if it does neither, so the new one can register.
  defp supersede(node_name, pid) do
    ref = Process.monitor(pid)
    send(pid, :sandbox_node_superseded)
    deadline = System.monotonic_time(:millisecond) + @supersede_timeout
    await_release(node_name, pid, ref, deadline)
  end

  defp await_release(node_name, pid, ref, deadline) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      @supersede_poll_ms ->
        cond do
          not registered_to?(node_name, pid) ->
            Process.demonitor(ref, [:flush])
            :ok

          System.monotonic_time(:millisecond) >= deadline ->
            Process.exit(pid, :kill)

            receive do
              {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
            after
              @supersede_timeout -> :ok
            end

          true ->
            await_release(node_name, pid, ref, deadline)
        end
    end
  end

  defp registered_to?(node_name, pid) do
    match?([{^pid, _info}], Registry.lookup(@registry, node_name))
  end

  def unregister(node_name) when is_binary(node_name) do
    Registry.unregister(@registry, node_name)
  end

  def update(node_name, info) when is_binary(node_name) and is_map(info) do
    case Registry.update_value(@registry, node_name, fn _ -> info end) do
      {_new, _old} -> :ok
      :error -> {:error, :not_connected}
    end
  end

  def lookup(node_name) when is_binary(node_name) do
    case Registry.lookup(@registry, node_name) do
      [{pid, info}] -> {:ok, pid, info}
      [] -> {:error, :not_connected}
    end
  end

  def lookup(_node_name), do: {:error, :not_connected}

  def connected?(node_name) do
    match?({:ok, _pid, _info}, lookup(node_name))
  end

  def connected_nodes do
    @registry
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.map(fn {name, pid, info} -> Map.merge(info, %{name: name, pid: pid}) end)
    |> Enum.sort_by(& &1.name)
  end

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
  Sends `op` with `args` to the node and waits for its result.

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
      send(pid, {:sandbox_command, ref, to_string(op), args, self()})
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
