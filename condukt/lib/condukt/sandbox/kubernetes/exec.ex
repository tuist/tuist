defmodule Condukt.Sandbox.Kubernetes.Exec do
  @moduledoc false

  alias Condukt.Sandbox.Kubernetes.State

  @stdin_chunk_size 32 * 1024

  def run(%State{} = state, command_list, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 120_000)

    state
    |> exec_op(command_list)
    |> K8s.Client.put_conn(state.conn)
    |> K8s.Client.run(recv_timeout: timeout)
    |> normalize_result()
  end

  def run_with_stdin(%State{} = state, command_list, input, opts \\ []) when is_binary(input) do
    timeout = Keyword.get(opts, :timeout, 120_000)
    parent = self()
    ref = make_ref()
    {collector, monitor_ref} = spawn_monitor(fn -> stream_collector(parent, ref, %{}) end)

    result =
      case K8s.Client.stream_to(state.conn, exec_op(state, command_list), [recv_timeout: timeout], collector) do
        {:ok, send_to_websocket} ->
          send_stdin(send_to_websocket, input)
          send_to_websocket.(:close)
          collect_stream(ref, monitor_ref, timeout)

        {:error, reason} ->
          {:error, format_api_error(reason)}
      end

    stop_collector(collector, monitor_ref)
    result
  end

  def shell_quote(s) when is_binary(s) do
    "'" <> String.replace(s, "'", "'\\''") <> "'"
  end

  def format_remote_error(""), do: :remote_error
  def format_remote_error(output) when is_binary(output), do: {:remote_error, output}

  defp exec_op(state, command_list) do
    K8s.Client.connect(
      "v1",
      "pods/exec",
      [namespace: state.namespace, name: state.pod_name],
      command: command_list,
      container: state.container,
      tty: false
    )
  end

  defp send_stdin(_send_to_websocket, ""), do: :ok

  defp send_stdin(send_to_websocket, input) when byte_size(input) <= @stdin_chunk_size do
    send_to_websocket.({:stdin, input})
    :ok
  end

  defp send_stdin(send_to_websocket, input) do
    <<chunk::binary-size(@stdin_chunk_size), rest::binary>> = input
    send_to_websocket.({:stdin, chunk})
    send_stdin(send_to_websocket, rest)
  end

  defp stream_collector(parent, ref, acc) do
    receive do
      {:open, true} ->
        stream_collector(parent, ref, acc)

      {:stdout, data} ->
        stream_collector(parent, ref, append_stream(acc, :stdout, data))

      {:stderr, data} ->
        stream_collector(parent, ref, append_stream(acc, :stderr, data))

      {:error, data} ->
        stream_collector(parent, ref, append_stream(acc, :error, data))

      {:close, _reason} ->
        send(parent, {ref, normalize_result({:ok, acc})})

      :done ->
        send(parent, {ref, normalize_result({:ok, acc})})
    end
  end

  defp append_stream(acc, key, data) do
    Map.update(acc, key, [data], &[data | &1])
  end

  defp collect_stream(ref, monitor_ref, timeout) do
    receive do
      {^ref, result} ->
        result

      {:DOWN, ^monitor_ref, :process, _pid, reason} ->
        {:error, {:exec_stream_collector_down, reason}}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp stop_collector(collector, monitor_ref) do
    Process.demonitor(monitor_ref, [:flush])
    Process.exit(collector, :shutdown)
  end

  defp normalize_result({:ok, response}) do
    stdout = response |> Map.get(:stdout, "") |> stream_to_binary()
    stderr = response |> Map.get(:stderr, "") |> stream_to_binary()
    error = response |> Map.get(:error, "") |> stream_to_binary()

    {:ok,
     %{
       output: stdout <> stderr,
       exit_code: derive_exit_code(error)
     }}
  end

  defp normalize_result({:error, reason}), do: {:error, format_api_error(reason)}

  defp stream_to_binary(nil), do: ""
  defp stream_to_binary(binary) when is_binary(binary), do: binary
  defp stream_to_binary(chunks) when is_list(chunks), do: chunks |> Enum.reverse() |> IO.iodata_to_binary()

  # K8s exec returns an error channel with a JSON-like status when the
  # remote command exits non-zero. Pull the exit code out of it if present.
  defp derive_exit_code(""), do: 0
  defp derive_exit_code(nil), do: 0

  defp derive_exit_code(error) when is_binary(error) do
    case Regex.run(~r/exit (?:status|code):?\s*(\d+)/i, error) do
      [_, code] -> String.to_integer(code)
      _ -> 1
    end
  end

  defp derive_exit_code(_), do: 1

  defp format_api_error(%{message: message}), do: message
  defp format_api_error(reason) when is_binary(reason), do: reason
  defp format_api_error(reason), do: inspect(reason)
end
