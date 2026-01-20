defmodule TuistWeb.Plugs.UeberauthHostPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.Plugs.UeberauthHostPlug

  setup :set_mimic_from_context

  describe "call/2" do
    test "sets x-forwarded-host header to the configured app URL host" do
      # Given
      conn = build_conn(:get, "/users/auth/github")
      opts = UeberauthHostPlug.init([])

      expect(Tuist.Environment, :app_url, fn [route_type: :app] ->
        "https://tuist.dev"
      end)

      # When
      conn = UeberauthHostPlug.call(conn, opts)

      # Then
      assert Plug.Conn.get_req_header(conn, "x-forwarded-host") == ["tuist.dev"]
    end

    test "sets x-forwarded-proto header to the configured app URL scheme" do
      # Given
      conn = build_conn(:get, "/users/auth/github")
      opts = UeberauthHostPlug.init([])

      expect(Tuist.Environment, :app_url, fn [route_type: :app] ->
        "https://tuist.dev"
      end)

      # When
      conn = UeberauthHostPlug.call(conn, opts)

      # Then
      assert Plug.Conn.get_req_header(conn, "x-forwarded-proto") == ["https"]
    end

    test "handles app URLs with non-standard ports" do
      # Given
      conn = build_conn(:get, "/users/auth/github")
      opts = UeberauthHostPlug.init([])

      expect(Tuist.Environment, :app_url, fn [route_type: :app] ->
        "http://localhost:4000"
      end)

      # When
      conn = UeberauthHostPlug.call(conn, opts)

      # Then
      assert Plug.Conn.get_req_header(conn, "x-forwarded-host") == ["localhost"]
      assert Plug.Conn.get_req_header(conn, "x-forwarded-proto") == ["http"]
    end

    test "overrides existing x-forwarded-host header from load balancer" do
      # Given
      conn =
        :get
        |> build_conn("/users/auth/github")
        |> Plug.Conn.put_req_header("x-forwarded-host", "tuist.onrender.com")
        |> Map.put(:host, "tuist.onrender.com")

      opts = UeberauthHostPlug.init([])

      expect(Tuist.Environment, :app_url, fn [route_type: :app] ->
        "https://tuist.dev"
      end)

      # When
      conn = UeberauthHostPlug.call(conn, opts)

      # Then
      # Should override the load balancer's forwarded host
      assert Plug.Conn.get_req_header(conn, "x-forwarded-host") == ["tuist.dev"]
      # Original host field remains unchanged
      assert conn.host == "tuist.onrender.com"
    end
  end
end
