defmodule TuistWeb.Plugs.CloseConnectionOnErrorPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import Plug.Test

  alias TuistWeb.Plugs.CloseConnectionOnErrorPlug

  describe "call/2" do
    test "adds Connection: close header for 4xx status codes" do
      # Given
      conn = conn(:get, "/")

      # When
      conn = CloseConnectionOnErrorPlug.call(conn, [])
      [before_send_hook] = conn.private.before_send
      conn = conn |> Plug.Conn.put_status(400) |> before_send_hook.()

      # Then
      assert Plug.Conn.get_resp_header(conn, "connection") == ["close"]
    end

    test "adds Connection: close header for 5xx status codes" do
      # Given
      conn = conn(:get, "/")

      # When
      conn = CloseConnectionOnErrorPlug.call(conn, [])
      [before_send_hook] = conn.private.before_send
      conn = conn |> Plug.Conn.put_status(500) |> before_send_hook.()

      # Then
      assert Plug.Conn.get_resp_header(conn, "connection") == ["close"]
    end

    test "does not add Connection: close header for 2xx status codes" do
      # Given
      conn = conn(:get, "/")

      # When
      conn = CloseConnectionOnErrorPlug.call(conn, [])
      [before_send_hook] = conn.private.before_send
      conn = conn |> Plug.Conn.put_status(200) |> before_send_hook.()

      # Then
      assert Plug.Conn.get_resp_header(conn, "connection") == []
    end

    test "does not add Connection: close header for 3xx status codes" do
      # Given
      conn = conn(:get, "/")

      # When
      conn = CloseConnectionOnErrorPlug.call(conn, [])
      [before_send_hook] = conn.private.before_send
      conn = conn |> Plug.Conn.put_status(302) |> before_send_hook.()

      # Then
      assert Plug.Conn.get_resp_header(conn, "connection") == []
    end
  end
end
