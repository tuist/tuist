defmodule Condukt.MCP.Client do
  @moduledoc """
  GenServer that owns the protocol state for a single MCP server
  connection.

  The process spawns the configured transport, performs the
  `initialize` / `notifications/initialized` / `tools/list` handshake,
  and then services synchronous tool calls from callers.

  In normal use, callers do not interact with this module directly:
  `Condukt.MCP.start_all/2` builds a list of clients and turns each
  server's tools into `Condukt.Tool.Inline` specs ready to drop into an
  agent tool list. Use `start_link/2` directly when you
  need finer control.
  """

  use GenServer

  alias Condukt.MCP.{JSONRPC, Server, Transport}

  @protocol_version "2025-03-26"
  @client_info %{"name" => "condukt", "version" => "1.0"}

  defstruct [
    :init_caller,
    :server,
    :transport_mod,
    :transport_pid,
    :server_info,
    next_id: 1,
    status: :starting,
    pending: %{},
    timers: %{},
    tools: []
  ]

  @doc """
  Starts a client and blocks the caller until the connection is ready
  or fails.

  Options:

    * `:name` - register the GenServer under a name
    * `:fetch_env` - injection point for env-backed auth/secret refs (testing)
    * `:token_request` - injection point for the OAuth token endpoint (testing)
    * `:sse_request` / `:http_request` - injection points for the HTTP
      transports (testing)
  """
  def start_link(%Server{} = server, opts \\ []) do
    parent = self()
    name = Keyword.get(opts, :name)
    start_arg = {server, opts, parent}

    gen_opts = if name, do: [name: name], else: []

    case GenServer.start_link(__MODULE__, start_arg, gen_opts) do
      {:ok, pid} -> wait_for_ready(pid, server.init_timeout)
      {:error, _} = err -> err
    end
  end

  defp wait_for_ready(pid, timeout) do
    receive do
      {:"$mcp_ready", ^pid, :ok} ->
        {:ok, pid}

      {:"$mcp_ready", ^pid, {:error, reason}} ->
        stop_safely(pid)
        {:error, reason}
    after
      timeout ->
        stop_safely(pid)
        {:error, :init_timeout}
    end
  end

  defp stop_safely(pid) do
    GenServer.cast(pid, :stop)
    :ok
  end

  @doc """
  Returns the cached `tools/list` descriptors discovered during
  initialization.
  """
  def tools(client), do: GenServer.call(client, :tools)

  @doc """
  Returns the `serverInfo` block returned by the server during the
  `initialize` handshake.
  """
  def server_info(client), do: GenServer.call(client, :server_info)

  @doc """
  Calls a tool on the connected server. The result is the raw `content`
  block returned by the server, normalized into a single string when
  the server returns text-only content. Errors include both transport
  errors and `isError: true` tool responses.
  """
  def call_tool(client, name, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout) || GenServer.call(client, :request_timeout)
    call_timeout = timeout + 1_000
    GenServer.call(client, {:call_tool, name, args, timeout}, call_timeout)
  end

  @doc "Stops the client and closes the underlying transport."
  def stop(client), do: stop_safely(client)

  @impl true
  def init({server, opts, parent}) do
    Process.flag(:trap_exit, true)

    case Server.normalize(server) do
      {:ok, server} ->
        state = %__MODULE__{init_caller: parent, server: server}
        {:ok, state, {:continue, {:start_transport, opts}}}

      {:error, reason} ->
        {:stop, {:invalid_server, reason}}
    end
  end

  @impl true
  def handle_continue({:start_transport, opts}, state) do
    transport_mod = Transport.implementation(state.server.transport)

    transport_opts =
      [server: state.server, owner: self()] ++
        Keyword.take(opts, [:fetch_env, :token_request, :sse_request, :http_request])

    case transport_mod.start_link(transport_opts) do
      {:ok, transport_pid} ->
        Process.link(transport_pid)

        state = %{state | transport_mod: transport_mod, transport_pid: transport_pid}
        state = send_initialize(state)
        {:noreply, %{state | status: :initializing}}

      {:error, reason} ->
        report_init_error(state, {:transport_failed, reason})
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_call(:tools, _from, state), do: {:reply, state.tools, state}

  def handle_call(:server_info, _from, state), do: {:reply, state.server_info, state}

  def handle_call(:request_timeout, _from, state), do: {:reply, state.server.request_timeout, state}

  def handle_call({:call_tool, name, args, timeout}, from, %{status: :ready} = state) do
    params = %{"name" => name, "arguments" => args || %{}}
    {state, id} = send_request(state, "tools/call", params, {:call_tool, from})
    timer = Process.send_after(self(), {:mcp_request_timeout, id}, timeout)
    state = %{state | timers: Map.put(state.timers, id, timer)}
    {:noreply, state}
  end

  def handle_call({:call_tool, _name, _args, _timeout}, _from, state) do
    {:reply, {:error, {:not_ready, state.status}}, state}
  end

  @impl true
  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl true
  def handle_info({:mcp_message, {:response, id, result}}, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        {:noreply, state}

      {kind, pending} ->
        {timer, timers} = Map.pop(state.timers, id)
        if timer, do: Process.cancel_timer(timer)
        handle_response(kind, result, %{state | pending: pending, timers: timers})
    end
  end

  def handle_info({:mcp_request_timeout, id}, state) do
    case Map.pop(state.pending, id) do
      {nil, _pending} ->
        {:noreply, state}

      {{:call_tool, from}, pending} ->
        GenServer.reply(from, {:error, :request_timeout})
        {:noreply, %{state | pending: pending, timers: Map.delete(state.timers, id)}}

      {_kind, pending} ->
        {:noreply, %{state | pending: pending, timers: Map.delete(state.timers, id)}}
    end
  end

  def handle_info({:mcp_message, {:request, _id, _method, _params}}, state) do
    # Server-initiated requests (sampling, roots) are not supported in v1.
    {:noreply, state}
  end

  def handle_info({:mcp_message, {:notification, _method, _params}}, state) do
    {:noreply, state}
  end

  def handle_info({:mcp_transport_down, reason}, state) do
    state = fail_pending(state, {:transport_down, reason})

    if state.status != :ready do
      report_init_error(state, {:transport_down, reason})
    end

    {:stop, :normal, state}
  end

  def handle_info({:EXIT, pid, _reason}, %{transport_pid: pid} = state) do
    state = fail_pending(state, :transport_exited)

    if state.status != :ready do
      report_init_error(state, :transport_exited)
    end

    {:stop, :normal, %{state | transport_pid: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{transport_pid: pid, transport_mod: mod}) when is_pid(pid) and not is_nil(mod) do
    if Process.alive?(pid), do: mod.close(pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp send_initialize(state) do
    params = %{
      "protocolVersion" => @protocol_version,
      "capabilities" => %{},
      "clientInfo" => @client_info
    }

    {state, _id} = send_request(state, "initialize", params, :init)
    state
  end

  defp send_request(state, method, params, kind) do
    id = state.next_id
    envelope = JSONRPC.request(id, method, params)

    case state.transport_mod.send_message(state.transport_pid, envelope) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end

    pending = Map.put(state.pending, id, kind)
    {%{state | next_id: id + 1, pending: pending}, id}
  end

  defp send_notification(state, method, params \\ nil) do
    envelope = JSONRPC.notification(method, params)
    state.transport_mod.send_message(state.transport_pid, envelope)
    state
  end

  defp handle_response(:init, {:ok, info}, state) do
    state = %{state | server_info: info}
    state = send_notification(state, "notifications/initialized")
    {state, _id} = send_request(state, "tools/list", %{}, :tools_list)
    {:noreply, %{state | status: :listing_tools}}
  end

  defp handle_response(:init, {:error, error}, state) do
    report_init_error(state, {:initialize_failed, error})
    {:stop, :normal, state}
  end

  defp handle_response(:tools_list, {:ok, %{"tools" => tools}}, state) when is_list(tools) do
    send(state.init_caller, {:"$mcp_ready", self(), :ok})
    {:noreply, %{state | tools: tools, status: :ready}}
  end

  defp handle_response(:tools_list, {:ok, _other}, state) do
    report_init_error(state, :tools_list_invalid)
    {:stop, :normal, state}
  end

  defp handle_response(:tools_list, {:error, error}, state) do
    report_init_error(state, {:tools_list_failed, error})
    {:stop, :normal, state}
  end

  defp handle_response({:call_tool, from}, {:ok, result}, state) do
    GenServer.reply(from, normalize_tool_result(result))
    {:noreply, state}
  end

  defp handle_response({:call_tool, from}, {:error, error}, state) do
    GenServer.reply(from, {:error, error})
    {:noreply, state}
  end

  defp normalize_tool_result(%{"isError" => true} = result) do
    {:error, render_content(result)}
  end

  defp normalize_tool_result(%{"content" => _} = result) do
    {:ok, render_content(result)}
  end

  defp normalize_tool_result(other), do: {:ok, other}

  defp render_content(%{"content" => parts}) when is_list(parts) do
    parts
    |> Enum.map(&render_content_part/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> ""
      [single] -> single
      many -> Enum.join(many, "\n")
    end
  end

  defp render_content(other), do: other

  defp render_content_part(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp render_content_part(part), do: JSON.encode!(part)

  defp report_init_error(state, reason) do
    send(state.init_caller, {:"$mcp_ready", self(), {:error, reason}})
  end

  defp fail_pending(state, reason) do
    Enum.each(state.timers, fn {_id, timer} -> Process.cancel_timer(timer) end)

    Enum.each(state.pending, fn
      {_id, {:call_tool, from}} -> GenServer.reply(from, {:error, reason})
      _ -> :ok
    end)

    %{state | pending: %{}, timers: %{}}
  end
end
