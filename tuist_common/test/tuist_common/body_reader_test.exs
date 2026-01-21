defmodule TuistCommon.BodyReaderTest do
  use ExUnit.Case, async: true

  alias TuistCommon.BodyReader

  describe "calculate_timeout/2" do
    test "returns minimum timeout for small content" do
      # 1MB at 50KB/s = 20 seconds, but minimum is 60 seconds
      assert BodyReader.calculate_timeout(1_000_000) == 60_000
    end

    test "calculates timeout based on content length for large content" do
      # 25MB at 50KB/s = 500 seconds
      assert BodyReader.calculate_timeout(25 * 1024 * 1024) == 512_000
    end

    test "respects custom min_timeout option" do
      assert BodyReader.calculate_timeout(1_000, min_timeout: 30_000) == 30_000
    end

    test "respects custom min_throughput option" do
      # 10MB at 100KB/s = 100 seconds
      assert BodyReader.calculate_timeout(10_000_000, min_throughput: 100_000) == 100_000
    end
  end

  describe "read_opts/2" do
    test "returns base opts with dynamic timeout when content-length is present" do
      conn = %Plug.Conn{req_headers: [{"content-length", "25000000"}]}
      opts = BodyReader.read_opts(conn, length: 50_000_000)

      assert Keyword.get(opts, :length) == 50_000_000
      assert Keyword.get(opts, :read_timeout) > 60_000
    end

    test "returns base opts with default timeout when content-length is missing" do
      conn = %Plug.Conn{req_headers: []}
      opts = BodyReader.read_opts(conn, length: 50_000_000)

      assert Keyword.get(opts, :length) == 50_000_000
      assert Keyword.get(opts, :read_timeout) == 60_000
    end

    test "returns base opts with default timeout for invalid content-length" do
      conn = %Plug.Conn{req_headers: [{"content-length", "invalid"}]}
      opts = BodyReader.read_opts(conn)

      assert Keyword.get(opts, :read_timeout) == 60_000
    end

    test "returns base opts with default timeout for negative content-length" do
      conn = %Plug.Conn{req_headers: [{"content-length", "-100"}]}
      opts = BodyReader.read_opts(conn)

      assert Keyword.get(opts, :read_timeout) == 60_000
    end

    test "removes min_timeout and min_throughput from final opts" do
      conn = %Plug.Conn{req_headers: [{"content-length", "1000000"}]}
      opts = BodyReader.read_opts(conn, min_timeout: 30_000, min_throughput: 100_000)

      refute Keyword.has_key?(opts, :min_timeout)
      refute Keyword.has_key?(opts, :min_throughput)
    end
  end

  describe "get_content_length/1" do
    test "returns content length as integer" do
      conn = %Plug.Conn{req_headers: [{"content-length", "12345"}]}
      assert BodyReader.get_content_length(conn) == 12345
    end

    test "returns nil when header is missing" do
      conn = %Plug.Conn{req_headers: []}
      assert BodyReader.get_content_length(conn) == nil
    end

    test "returns nil for invalid content length" do
      conn = %Plug.Conn{req_headers: [{"content-length", "not-a-number"}]}
      assert BodyReader.get_content_length(conn) == nil
    end

    test "returns nil for negative content length" do
      conn = %Plug.Conn{req_headers: [{"content-length", "-1"}]}
      assert BodyReader.get_content_length(conn) == nil
    end

    test "returns nil for content length with trailing characters" do
      conn = %Plug.Conn{req_headers: [{"content-length", "123abc"}]}
      assert BodyReader.get_content_length(conn) == nil
    end
  end
end
