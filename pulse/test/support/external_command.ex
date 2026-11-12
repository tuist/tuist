defmodule Pulse.Test.ExternalCommand do
  @moduledoc "Owns one optional interoperability subprocess, with bounded logs and supervised cleanup."
  use GenServer, restart: :temporary

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
  def ready(pid), do: GenServer.call(pid, :ready, 15_000)
  def await(pid), do: GenServer.call(pid, :await, 30_000)
  def stop(pid), do: GenServer.call(pid, :stop, 15_000)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    path = Keyword.fetch!(opts, :path) |> Path.expand()
    args = Enum.map(Keyword.get(opts, :args, []), &String.to_charlist/1)
    isolate_beam? = Keyword.get(opts, :isolate_beam, false)

    env =
      System.get_env()
      |> Map.keys()
      |> Enum.filter(fn key ->
        String.starts_with?(key, ["OTEL_", "GRPC_"]) or
          (isolate_beam? and String.starts_with?(key, ["ERL_", "ELIXIR_", "MIX_"])) or
          key in ~w(GODEBUG GOMEMLIMIT GOMAXPROCS HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy)
      end)
      |> Enum.map(&{String.to_charlist(&1), false})

    env = [{~c"GOMAXPROCS", ~c"2"} | Enum.reject(env, fn {key, _} -> key == ~c"GOMAXPROCS" end)]

    # Only this explicitly supplied header setting survives OTEL_* scrubbing.
    # Optional client fixtures own these synthetic credentials; no endpoint
    # override is accepted here.
    env =
      case Keyword.get(opts, :otel_trace_headers) do
        nil ->
          env

        headers when is_binary(headers) ->
          key = ~c"OTEL_EXPORTER_OTLP_TRACES_HEADERS"
          [{key, String.to_charlist(headers)} | List.keydelete(env, key, 0)]
      end

    port =
      Port.open({:spawn_executable, String.to_charlist(path)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        env: env
      ])

    {:ok, %{port: port, output: "", status: nil, ready?: false, waiters: [], ready_waiters: []}}
  end

  @impl true
  def handle_call(:ready, from, state) do
    cond do
      state.ready? -> {:reply, :ok, state}
      state.status != nil -> {:reply, {:error, state.status, state.output}, state}
      true -> {:noreply, %{state | ready_waiters: [from | state.ready_waiters]}}
    end
  end

  def handle_call(:await, from, %{status: nil} = state), do: {:noreply, %{state | waiters: [from | state.waiters]}}
  def handle_call(:await, _from, state), do: {:reply, {state.status, state.output}, state}

  def handle_call(:stop, from, %{status: nil} = state) do
    signal(state.port, "-TERM")
    {:noreply, %{state | waiters: [from | state.waiters]}}
  end

  def handle_call(:stop, _from, state), do: {:reply, {state.status, state.output}, state}

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    output = state.output <> data
    output = binary_part(output, max(0, byte_size(output) - 65_536), min(byte_size(output), 65_536))
    ready? = state.ready? or String.contains?(output, "Everything is ready")
    if ready?, do: Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))
    {:noreply, %{state | output: output, ready?: ready?, ready_waiters: if(ready?, do: [], else: state.ready_waiters)}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Enum.each(state.waiters, &GenServer.reply(&1, {status, state.output}))
    Enum.each(state.ready_waiters, &GenServer.reply(&1, {:error, status, state.output}))
    {:noreply, %{state | status: status, waiters: [], ready_waiters: []}}
  end

  # System.cmd/3 used for signalling owns a short-lived port too.
  def handle_info({:EXIT, port, _reason}, state) when is_port(port), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{status: nil, port: port}) do
    signal(port, "-KILL")
    if Port.info(port), do: Port.close(port)
  end

  def terminate(_reason, _state), do: :ok

  defp signal(port, signal) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("/bin/kill", [signal, Integer.to_string(pid)], stderr_to_stdout: true)
      nil -> :ok
    end
  end
end
