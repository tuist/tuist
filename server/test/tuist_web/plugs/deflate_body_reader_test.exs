defmodule TuistWeb.Plugs.DeflateBodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Plug.Parsers.RequestTooLargeError
  alias TuistWeb.Plugs.DeflateBodyReader

  defp parse(body, headers, length \\ 1_000_000, path \\ "/") do
    opts =
      Plug.Parsers.init(
        parsers: [:json],
        json_decoder: Phoenix.json_library(),
        body_reader: {DeflateBodyReader, :read_body, []},
        length: length
      )

    conn =
      Enum.reduce(headers, conn(:post, path, body), fn {key, value}, conn ->
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

    assert_raise RequestTooLargeError, fn ->
      parse(deflate(body), [{"content-encoding", "deflate"} | @json], 1_000)
    end
  end

  test "Gradle publishing has an 8MB plain and decompressed cap before ingestion" do
    body = JSON.encode!(%{"padding" => String.duplicate("a", 8_000_001)})
    path = "/api/projects/organization/project/gradle/builds"

    for {payload, headers} <- [{body, @json}, {deflate(body), [{"content-encoding", "deflate"} | @json]}] do
      assert_raise RequestTooLargeError, fn ->
        parse(payload, headers, 50_000_000, path)
      end
    end
  end

  test "credential-bearing Gradle requests retain the existing larger body limit" do
    body = JSON.encode!(%{"padding" => String.duplicate("a", 8_000_001)})

    for {payload, headers} <- [{body, @json}, {deflate(body), [{"content-encoding", "deflate"} | @json]}] do
      parsed =
        parse(
          payload,
          [{"authorization", "Bearer supplied-token"} | headers],
          50_000_000,
          "/api/projects/account/project/gradle/builds"
        )

      assert byte_size(parsed.body_params["padding"]) == 8_000_001
    end
  end

  test "rejects a body that is not valid DEFLATE" do
    assert_raise Plug.BadRequestError, fn ->
      parse("not deflate", [{"content-encoding", "deflate"} | @json])
    end
  end
end
