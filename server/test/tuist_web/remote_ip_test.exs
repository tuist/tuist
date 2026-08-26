defmodule TuistWeb.RemoteIpTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  describe "get/1" do
    test "prefers the Cloudflare connecting IP header" do
      # Given
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("cf-connecting-ip", " 203.0.113.10 ")
        |> Plug.Conn.put_req_header("x-forwarded-for", "spoofed-ip, 173.245.48.10")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "203.0.113.10"
    end

    test "prefers the Cloudflare header when directly connected to a Cloudflare IPv6 address" do
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {0x2606, 0x4700, 0, 0, 0, 0, 0, 1})
        |> Plug.Conn.put_req_header("cf-connecting-ip", "2001:db8::1")
        |> Plug.Conn.put_req_header("x-forwarded-for", "spoofed-ip")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "2001:db8::1"
    end

    test "ignores the Cloudflare header from an untrusted hop" do
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 20})
        |> Plug.Conn.put_req_header("cf-connecting-ip", "198.51.100.10")
        |> Plug.Conn.put_req_header("x-forwarded-for", "forwarded-ip, 198.51.100.20")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "forwarded-ip"
    end

    test "ignores an invalid Cloudflare address from a trusted hop" do
      # Given
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("cf-connecting-ip", "not-an-ip")
        |> Plug.Conn.put_req_header("x-forwarded-for", "forwarded-ip, 173.245.48.10")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "forwarded-ip"
    end

    test "falls back to the first forwarded IP when the Cloudflare header is not present" do
      # Given
      conn = build_conn()
      conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", " ip-one, ip-two")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "ip-one"
    end

    test "ignores empty forwarding headers" do
      # Given
      conn =
        build_conn()
        |> Plug.Conn.put_req_header("cf-connecting-ip", "  ")
        |> Plug.Conn.put_req_header("x-forwarded-for", " , ip-two")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "ip-two"
    end

    test "gets the connection address when forwarding headers are not present" do
      # Given
      conn = build_conn()

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "127.0.0.1"
    end
  end

  describe "origin/1" do
    test "reads the country the edge resolved" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "FR"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "FR"
    end

    test "narrows to a subdivision in the countries holding more than one region" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "US"}, {"cf-region-code", "OR"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "US-OR"
    end

    test "keeps the country when the subdivision header is absent" do
      # The subdivision rides a managed transform rather than the default
      # header set, so an unconfigured zone must answer coarsely, not wrongly.
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "US"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "US"
    end

    test "ignores a subdivision for a country that has only one region" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "FR"}, {"cf-region-code", "IDF"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "FR"
    end

    test "answers nothing for an untrusted hop" do
      # The header is trivially forgeable, so an account could otherwise vote
      # itself into a region by setting it.
      # Given
      conn =
        build_conn()
        |> Map.put(:remote_ip, {203, 0, 113, 20})
        |> Plug.Conn.put_req_header("cf-ipcountry", "FR")

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == nil
    end

    test "answers nothing when the edge could not place the address" do
      for country <- ["XX", "T1", "", "not-a-country"] do
        conn = cloudflare_conn([{"cf-ipcountry", country}])

        assert TuistWeb.RemoteIp.origin(conn) == nil
      end
    end

    test "answers nothing when the edge sent no country at all" do
      # Given
      conn = cloudflare_conn([])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == nil
    end

    test "rejects a malformed subdivision rather than carrying it into a label" do
      # Given
      conn = cloudflare_conn([{"cf-ipcountry", "US"}, {"cf-region-code", "not a code"}])

      # When
      got = TuistWeb.RemoteIp.origin(conn)

      # Then
      assert got == "US"
    end
  end

  # A private peer whose last forwarded hop is Cloudflare, which is the trusted
  # shape `get/1` already establishes.
  defp cloudflare_conn(headers) do
    conn = Plug.Conn.put_req_header(build_conn(), "x-forwarded-for", "203.0.113.10, 173.245.48.10")

    Enum.reduce(headers, conn, fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
  end
end
