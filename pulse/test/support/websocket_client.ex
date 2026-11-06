defmodule Pulse.Test.WebSocketClient do
  @moduledoc """
  Minimal RFC 6455 client over `:gen_tcp` for tests: opens a connection,
  performs the upgrade and reads unmasked server frames. Only what the
  live tail tests need; not a general client.
  """

  @spec connect(:inet.port_number(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, port()} | {:error, {integer(), binary()}}
  def connect(port, path, headers \\ []) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw])
    key = Base.encode64(:crypto.strong_rand_bytes(16))

    request =
      [
        "GET #{path} HTTP/1.1\r\n",
        "host: 127.0.0.1:#{port}\r\n",
        "upgrade: websocket\r\n",
        "connection: Upgrade\r\n",
        "sec-websocket-key: #{key}\r\n",
        "sec-websocket-version: 13\r\n",
        Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
        "\r\n"
      ]

    :ok = :gen_tcp.send(socket, request)
    {status, rest} = read_head(socket, "")

    if status == 101 do
      Process.put({__MODULE__, socket}, rest)
      {:ok, socket}
    else
      :gen_tcp.close(socket)
      {:error, {status, rest}}
    end
  end

  @doc "Next text frame's decoded JSON, skipping control frames."
  @spec next_json(port(), timeout()) :: map()
  def next_json(socket, timeout \\ 30_000) do
    case next_frame(socket, timeout) do
      {:text, payload} -> JSON.decode!(payload)
      {_control, _payload} -> next_json(socket, timeout)
    end
  end

  @spec next_frame(port(), timeout()) :: {:text | :binary | :ping | :pong | :close, binary()}
  def next_frame(socket, timeout \\ 30_000) do
    <<_fin::1, _rsv::3, opcode::4, 0::1, len::7>> = take(socket, 2, timeout)

    len =
      case len do
        126 -> :binary.decode_unsigned(take(socket, 2, timeout))
        127 -> :binary.decode_unsigned(take(socket, 8, timeout))
        n -> n
      end

    payload = take(socket, len, timeout)
    {opcode(opcode), payload}
  end

  def close(socket), do: :gen_tcp.close(socket)

  defp opcode(1), do: :text
  defp opcode(2), do: :binary
  defp opcode(8), do: :close
  defp opcode(9), do: :ping
  defp opcode(10), do: :pong

  defp take(_socket, 0, _timeout), do: ""

  defp take(socket, n, timeout) do
    buffered = Process.get({__MODULE__, socket}, "")

    if byte_size(buffered) >= n do
      <<chunk::binary-size(^n), rest::binary>> = buffered
      Process.put({__MODULE__, socket}, rest)
      chunk
    else
      {:ok, data} = :gen_tcp.recv(socket, 0, timeout)
      Process.put({__MODULE__, socket}, buffered <> data)
      take(socket, n, timeout)
    end
  end

  defp read_head(socket, acc) do
    case :binary.split(acc, "\r\n\r\n") do
      [head, rest] ->
        ["HTTP/1.1 " <> <<status::binary-size(3)>> <> _ | _] = String.split(head, "\r\n")
        {String.to_integer(status), rest}

      [_] ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 30_000)
        read_head(socket, acc <> data)
    end
  end
end
