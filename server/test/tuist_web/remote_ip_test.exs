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
end
