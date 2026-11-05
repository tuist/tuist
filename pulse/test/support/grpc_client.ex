defmodule Pulse.Test.GRPCClient do
  @moduledoc false
  # Minimal unary gRPC client over Mint's HTTP/2 (h2c prior knowledge), so
  # receiver tests need no external tools. Returns the response message,
  # grpc-status/message and raw trailers.

  def unary(port, path, message, opts \\ []) do
    {:ok, conn} = Mint.HTTP2.connect(:http, "127.0.0.1", port, mode: :passive)

    {flag, payload} =
      if opts[:gzip], do: {1, :zlib.gzip(message)}, else: {0, message}

    headers =
      [
        {"content-type", "application/grpc"},
        {"te", "trailers"}
      ] ++ if(opts[:gzip], do: [{"grpc-encoding", "gzip"}], else: []) ++ Keyword.get(opts, :metadata, [])

    {:ok, conn, ref} =
      Mint.HTTP2.request(conn, "POST", path, headers, <<flag, byte_size(payload)::32, payload::binary>>)

    {conn, response} = collect(conn, ref, %{headers: [], data: "", trailers: []})
    Mint.HTTP2.close(conn)

    metadata = response.headers ++ response.trailers

    %{
      status: metadata |> List.keyfind("grpc-status", 0, {nil, nil}) |> elem(1) |> parse_status(),
      message: metadata |> List.keyfind("grpc-message", 0, {nil, ""}) |> elem(1) |> URI.decode(),
      details: metadata |> List.keyfind("grpc-status-details-bin", 0, {nil, nil}) |> elem(1) |> decode_details(),
      body: unframe(response.data, metadata)
    }
  end

  defp collect(conn, ref, acc) do
    {:ok, conn, responses} = Mint.HTTP2.recv(conn, 0, 10_000)

    acc =
      Enum.reduce(responses, acc, fn
        {:status, ^ref, _status}, acc -> acc
        {:headers, ^ref, headers}, %{data: ""} = acc -> %{acc | headers: acc.headers ++ headers}
        {:headers, ^ref, trailers}, acc -> %{acc | trailers: trailers}
        {:data, ^ref, data}, acc -> %{acc | data: acc.data <> data}
        {:done, ^ref}, acc -> Map.put(acc, :done, true)
        _, acc -> acc
      end)

    if Map.get(acc, :done), do: {conn, acc}, else: collect(conn, ref, acc)
  end

  defp parse_status(nil), do: nil
  defp parse_status(value), do: String.to_integer(value)

  defp decode_details(nil), do: nil

  defp decode_details(value) do
    padded = value <> String.duplicate("=", rem(4 - rem(byte_size(value), 4), 4))
    Base.decode64!(padded)
  end

  defp unframe(<<>>, _metadata), do: nil
  defp unframe(<<0, size::32, message::binary-size(size)>>, _metadata), do: message
  defp unframe(<<1, size::32, message::binary-size(size)>>, _metadata), do: :zlib.gunzip(message)
end
