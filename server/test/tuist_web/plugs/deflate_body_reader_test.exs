defmodule TuistWeb.Plugs.DeflateBodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias TuistWeb.Plugs.DeflateBodyReader

  defp parse(body, headers, length \\ 1_000_000) do
    opts =
      Plug.Parsers.init(
        parsers: [:json],
        json_decoder: Phoenix.json_library(),
        body_reader: {DeflateBodyReader, :read_body, []},
        length: length
      )

    conn =
      Enum.reduce(headers, conn(:post, "/", body), fn {key, value}, conn ->
        Plug.Conn.put_req_header(conn, key, value)
      end)

    Plug.Parsers.call(conn, opts)
  end

  defp deflate(data) do
    z = :zlib.open()
    :ok = :zlib.deflateInit(z, :default, :deflated, -15, 8, :default)
    compressed = IO.iodata_to_binary([:zlib.deflate(z, data), :zlib.deflate(z, [], :finish)])
    :zlib.close(z)
    compressed
  end

  @json [{"content-type", "application/json"}]

  test "parses a raw DEFLATE body" do
    body = JSON.encode!(%{"files" => Enum.to_list(1..1_000)})

    conn = parse(deflate(body), [{"content-encoding", "deflate"} | @json])

    assert conn.body_params["files"] == Enum.to_list(1..1_000)
  end

  test "reads an uncompressed body as before" do
    conn = parse(JSON.encode!(%{"status" => "success"}), @json)

    assert conn.body_params == %{"status" => "success"}
  end

  test "rejects a body that decompresses past the length limit" do
    # Highly repetitive, so the compressed body is far below the limit.
    body = JSON.encode!(%{"padding" => String.duplicate("a", 2_000)})

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      parse(deflate(body), [{"content-encoding", "deflate"} | @json], 1_000)
    end
  end

  test "rejects a body that is not valid DEFLATE" do
    assert_raise Plug.BadRequestError, fn ->
      parse("not deflate", [{"content-encoding", "deflate"} | @json])
    end
  end
end
