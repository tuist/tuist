defmodule PulseWeb.CompressedBodyReaderTest do
  use Pulse.Test.Case, async: true

  alias Plug.Parsers.RequestTooLargeError
  alias PulseWeb.CompressedBodyReader

  defp gzip(body) do
    conn = Plug.Test.conn(:post, "/v1/traces") |> Plug.Conn.put_req_header("content-encoding", "gzip")
    CompressedBodyReader.decompress(conn, body)
  end

  test "empty gzip members and overlapping zero trailers decode correctly" do
    empty = :zlib.gzip("")
    assert {:ok, ""} = gzip(empty)
    assert {:ok, "payload"} = gzip(empty <> :zlib.gzip("payload") <> empty)
    assert {:ok, ""} = gzip(:binary.copy(empty, 64))
  end

  test "even empty members consume the fixed gzip work ceiling" do
    empty = :zlib.gzip("")
    assert {:error, :payload_too_large} = gzip(:binary.copy(empty, 65))
    assert {:error, :payload_too_large} = gzip(:binary.copy(empty, 10_000))
  end

  test "member caps do not weaken CRC, trailer and cumulative output validation" do
    assert {:error, :invalid_gzip} = gzip("")
    assert {:error, :invalid_gzip} = gzip(binary_part(:zlib.gzip("hello"), 0, 15))
    Pulse.Runtime.put_env(:pulse, CompressedBodyReader, max_decompressed_bytes: 5)
    assert {:ok, "hello"} = gzip(:zlib.gzip("hello"))
    assert {:error, :payload_too_large} = gzip(:zlib.gzip("hello") <> :zlib.gzip("!"))
  end

  test "deflate is opt-in and uses the exact shared expansion boundary" do
    Pulse.Runtime.put_env(:pulse, CompressedBodyReader, max_decompressed_bytes: 5)
    compressed = :zlib.compress("hello")

    conn =
      :post
      |> Plug.Test.conn("/api/42/store/", compressed)
      |> Plug.Conn.put_req_header("content-encoding", "deflate")

    assert {:ok, ^compressed, _} = CompressedBodyReader.read_body(conn, [])
    assert {:ok, ^compressed} = CompressedBodyReader.decompress(conn, compressed)
    assert {:ok, "hello", _} = CompressedBodyReader.read_body(conn, deflate: true)

    too_large =
      :post
      |> Plug.Test.conn("/api/42/store/", :zlib.compress("hello!"))
      |> Plug.Conn.put_req_header("content-encoding", "deflate")

    assert_raise RequestTooLargeError, fn ->
      CompressedBodyReader.read_body(too_large, deflate: true)
    end
  end

  test "zstd is opt-in, bounds streaming output and requires complete frames" do
    Pulse.Runtime.put_env(:pulse, CompressedBodyReader, max_decompressed_bytes: 5)

    for options <- [%{checksumFlag: true}, %{contentSizeFlag: false}] do
      compressed = "hello" |> :zstd.compress(options) |> IO.iodata_to_binary()
      conn = Plug.Test.conn(:post, "/api/42/store/", compressed) |> Plug.Conn.put_req_header("content-encoding", "zstd")
      assert {:ok, ^compressed, _} = CompressedBodyReader.read_body(conn, [])
      assert {:ok, ^compressed} = CompressedBodyReader.decompress(conn, compressed)
      assert {:ok, "hello", _} = CompressedBodyReader.read_body(conn, zstd: true)

      for size <- 0..(byte_size(compressed) - 1) do
        truncated = binary_part(compressed, 0, size)

        conn =
          Plug.Test.conn(:post, "/api/42/store/", truncated) |> Plug.Conn.put_req_header("content-encoding", "zstd")

        assert {:error, :invalid_zstd} = CompressedBodyReader.read_body(conn, zstd: true)
      end

      too_large = "hello!" |> :zstd.compress(options) |> IO.iodata_to_binary()
      conn = Plug.Test.conn(:post, "/api/42/store/", too_large) |> Plug.Conn.put_req_header("content-encoding", "zstd")
      assert_raise RequestTooLargeError, fn -> CompressedBodyReader.read_body(conn, zstd: true) end
    end

    # No-content-size frame: distinguish the decoder-window ceiling from the
    # much smaller injected output ceiling, and exercise raw/RLE block geometry.
    for {body, expected} <- [
          {<<0x28, 0xB5, 0x2F, 0xFD, 0, 0x70, 41, 0, 0, "hello">>, "hello"},
          {<<0x28, 0xB5, 0x2F, 0xFD, 0x20, 5, 43, 0, 0, "a">>, "aaaaa"}
        ] do
      conn = Plug.Test.conn(:post, "/api/42/store/", body) |> Plug.Conn.put_req_header("content-encoding", "zstd")
      assert {:ok, ^expected, _} = CompressedBodyReader.read_body(conn, zstd: true)
    end

    oversized_window = <<0x28, 0xB5, 0x2F, 0xFD, 0, 0x78, 41, 0, 0, "hello">>

    conn =
      Plug.Test.conn(:post, "/api/42/store/", oversized_window) |> Plug.Conn.put_req_header("content-encoding", "zstd")

    assert_raise RequestTooLargeError, fn -> CompressedBodyReader.read_body(conn, zstd: true) end
  end
end
