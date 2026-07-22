defmodule TuistWeb.RemoteIpTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  describe "get/1" do
    test "prefers the Cloudflare connecting IP header" do
      # Given
      conn = build_conn()

      conn =
        conn
        |> Plug.Conn.put_req_header("cf-connecting-ip", " cloudflare-ip ")
        |> Plug.Conn.put_req_header("x-forwarded-for", "spoofed-ip, forwarded-ip")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "cloudflare-ip"
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
