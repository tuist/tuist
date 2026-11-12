defmodule Condukt.MCP.Transport.Stdio do
  @moduledoc false

  # Stdio MCP transport. Spawns the configured executable as a child
  # process and exchanges newline-delimited JSON-RPC envelopes over its
  # stdin/stdout. The subprocess is owned by an Erlang Port; closing the
  # port (or terminating this GenServer) closes the subprocess's stdin
  # and triggers its shutdown.

  use GenServer

  alias Condukt.MCP.JSONRPC

  defstruct [:owner, :port, :buffer, :command]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def send_message(pid, envelope), do: GenServer.call(pid, {:send, envelope})

  def close(pid) do
    GenServer.cast(pid, :stop)
    :ok
  end

  @impl GenServer
  def init(opts) do
    Process.flag(:trap_exit, true)

    server = Keyword.fetch!(opts, :server)
    owner = Keyword.fetch!(opts, :owner)
    {:stdio, transport_opts} = server.transport
    command = Keyword.fetch!(transport_opts, :command)
    args = Keyword.get(transport_opts, :args, [])
    cwd = Keyword.get(transport_opts, :cwd)

    case resolve_executable(command) do
      {:ok, path} ->
        env = build_env(server, opts)

        port_opts =
          [
            :binary,
            :exit_status,
            :use_stdio,
            :hide,
            args: args,
            env: env
          ]
          |> maybe_put_cwd(cwd)

        port = Port.open({:spawn_executable, path}, port_opts)
        {:ok, %__MODULE__{owner: owner, port: port, buffer: <<>>, command: command}}

      {:error, reason} ->
        {:stop, {:executable_not_found, command, reason}}
    end
  end

  defp resolve_executable(command) do
    cond do
      File.regular?(command) -> {:ok, command}
      path = System.find_executable(command) -> {:ok, path}
      true -> {:error, :enoent}
    end
  end

  defp maybe_put_cwd(opts, nil), do: opts
  defp maybe_put_cwd(opts, cwd), do: Keyword.put(opts, :cd, String.to_charlist(cwd))

  defp build_env(server, opts) do
    fetch_env = Keyword.get(opts, :fetch_env, &System.fetch_env/1)

    server.env
    |> normalize_env_spec()
    |> Enum.reduce([], fn {name, ref}, acc ->
      case resolve_env_value(ref, fetch_env) do
        {:ok, value} ->
          [{String.to_charlist(name), String.to_charlist(value)} | acc]

        :error ->
          acc
      end
    end)
  end

  defp normalize_env_spec(nil), do: []

  defp normalize_env_spec(list) when is_list(list) do
    Enum.map(list, fn name when is_binary(name) -> {name, {:env, name}} end)
  end

  defp normalize_env_spec(map) when is_map(map) do
    Enum.map(map, fn {name, ref} -> {to_string(name), ref} end)
  end

  defp resolve_env_value({:env, name}, fetch_env), do: fetch_env.(name)
  defp resolve_env_value({:static, value}, _fetch_env), do: {:ok, to_string(value)}
  defp resolve_env_value(value, _fetch_env) when is_binary(value), do: {:ok, value}
  defp resolve_env_value(_other, _fetch_env), do: :error

  @impl GenServer
  def handle_call({:send, envelope}, _from, %{port: port} = state) when is_port(port) do
    if Port.info(port) do
      Port.command(port, JSONRPC.encode_line!(envelope))
      {:reply, :ok, state}
    else
      {:reply, {:error, :port_closed}, state}
    end
  end

  def handle_call({:send, _envelope}, _from, state) do
    {:reply, {:error, :no_port}, state}
  end

  @impl GenServer
  def handle_cast(:stop, state), do: {:stop, :normal, state}

  @impl GenServer
  def handle_info({port, {:data, chunk}}, %{port: port} = state) when is_binary(chunk) do
    {:noreply, consume(state, chunk)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    send(state.owner, {:mcp_transport_down, {:exit, status}})
    {:stop, :normal, %{state | port: nil}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp consume(state, chunk) do
    {lines, rest} = split_lines(state.buffer <> chunk)
    Enum.each(lines, &forward_line(state.owner, &1))
    %{state | buffer: rest}
  end

  defp split_lines(binary) do
    case :binary.split(binary, "\n", [:global]) do
      [single] -> {[], single}
      parts -> Enum.split(parts, length(parts) - 1) |> finalize_split()
    end
  end

  defp finalize_split({lines, [trailing]}) do
    lines = lines |> Enum.map(&trim_carriage_return/1) |> Enum.reject(&(&1 == ""))
    {lines, trailing}
  end

  defp trim_carriage_return(line) do
    if String.ends_with?(line, "\r"), do: String.slice(line, 0..-2//1), else: line
  end

  defp forward_line(owner, line) do
    case JSONRPC.decode_and_classify(line) do
      {:error, _} -> :ok
      classified -> send(owner, {:mcp_message, classified})
    end
  end

  @impl GenServer
  def terminate(_reason, %{port: port}) when is_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
