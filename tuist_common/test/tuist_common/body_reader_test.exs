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

    test "caps timeout at max_timeout for very large content" do
      # 100GB would be way over 10 minutes, but capped at 600_000ms (10 minutes)
      assert BodyReader.calculate_timeout(100_000_000_000) == 600_000
    end

    test "respects custom min_timeout option" do
      assert BodyReader.calculate_timeout(1_000, min_timeout: 30_000) == 30_000
    end

    test "respects custom max_timeout option" do
      # 50MB at 50KB/s = 1000 seconds, but capped at 300 seconds
      assert BodyReader.calculate_timeout(50_000_000, max_timeout: 300_000) == 300_000
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
      # Should be capped at max
      assert Keyword.get(opts, :read_timeout) <= 600_000
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

    test "removes internal opts from final result" do
      conn = %Plug.Conn{req_headers: [{"content-length", "1000000"}]}
      opts = BodyReader.read_opts(conn, min_timeout: 30_000, max_timeout: 120_000, min_throughput: 100_000)

      refute Keyword.has_key?(opts, :min_timeout)
      refute Keyword.has_key?(opts, :max_timeout)
      refute Keyword.has_key?(opts, :min_throughput)
    end

    test "caps timeout at max_timeout for spoofed large content-length" do
      # Simulates potential abuse: huge Content-Length to get enormous timeout
      conn = %Plug.Conn{req_headers: [{"content-length", "999999999999"}]}
      opts = BodyReader.read_opts(conn)

      # Should be capped at 10 minutes (600_000ms)
      assert Keyword.get(opts, :read_timeout) == 600_000
    end
  end

  describe "chunk_timeout/1" do
    test "returns minimum timeout for small chunks" do
      # 256KB at 50KB/s = ~5 seconds, but min is 15 seconds
      assert BodyReader.chunk_timeout() == 15_000
    end

    test "calculates timeout based on read_length for larger chunks" do
      # 1MB at 50KB/s (51200 bytes/s) = ~19.5 seconds
      result = BodyReader.chunk_timeout(read_length: 1_000_000)
      assert result >= 19_000
      assert result <= 20_000
    end

    test "caps at max_timeout for very large chunks" do
      # 10MB at 50KB/s = ~200 seconds, but capped at 60 seconds by default
      assert BodyReader.chunk_timeout(read_length: 10_000_000) == 60_000
    end

    test "respects custom min_timeout" do
      # 256KB at 50KB/s = ~5 seconds, with min_timeout: 5_000 it should use calculated value
      # which is slightly above 5000 (5120ms), so use a small read_length to force min
      assert BodyReader.chunk_timeout(read_length: 1_000, min_timeout: 5_000) == 5_000
    end

    test "respects custom max_timeout" do
      assert BodyReader.chunk_timeout(read_length: 10_000_000, max_timeout: 30_000) == 30_000
    end

    test "respects custom min_throughput" do
      # 256KB at 10KB/s = ~26 seconds
      result = BodyReader.chunk_timeout(min_throughput: 10_000)
      assert result > 15_000
      assert result < 30_000
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
