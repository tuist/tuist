defmodule TuistWeb.RemoteIpTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  describe "get/1" do
    test "gets ip from the forwarder-for header when there's only one" do
      # Given
      conn = build_conn()
      conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "ip-one")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "ip-one"
    end

    test "gets ip from the forwarder-for header when there are multiple" do
      # Given
      conn = build_conn()
      conn = Plug.Conn.put_req_header(conn, "x-forwarded-for", "ip-one, ip-two")

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "ip-one"
    end

    test "gets default value when the x-forwarded-for headre is not present" do
      # Given
      conn = build_conn()

      # When
      got = TuistWeb.RemoteIp.get(conn)

      # Then
      assert got == "127.0.0.1"
    end
  end
end
