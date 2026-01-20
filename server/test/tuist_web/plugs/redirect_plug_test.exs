defmodule TuistWeb.RedirectPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.RedirectPlug

  describe "call/2" do
    test "redirects to new path preserving account_handle and project_handle", %{conn: conn} do
      conn = %{
        conn
        | path_params: %{"account_handle" => "acme", "project_handle" => "ios-app"}
      }

      opts = [to: "/module-cache/cache-runs"]

      conn = RedirectPlug.call(conn, opts)

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/acme/ios-app/module-cache/cache-runs"
      assert conn.halted
    end

    test "preserves query string when present", %{conn: conn} do
      conn = %{
        conn
        | path_params: %{"account_handle" => "acme", "project_handle" => "ios-app"},
          query_string: "page=2&limit=10"
      }

      opts = [to: "/module-cache/cache-runs"]

      conn = RedirectPlug.call(conn, opts)

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/acme/ios-app/module-cache/cache-runs?page=2&limit=10"
      assert conn.halted
    end

    test "handles empty query string", %{conn: conn} do
      conn = %{
        conn
        | path_params: %{"account_handle" => "acme", "project_handle" => "ios-app"},
          query_string: ""
      }

      opts = [to: "/module-cache/cache-runs"]

      conn = RedirectPlug.call(conn, opts)

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/acme/ios-app/module-cache/cache-runs"
      assert conn.halted
    end

    test "uses 301 moved permanently status", %{conn: conn} do
      conn = %{
        conn
        | path_params: %{"account_handle" => "acme", "project_handle" => "ios-app"}
      }

      opts = [to: "/new-path"]

      conn = RedirectPlug.call(conn, opts)

      assert conn.status == 301
    end
  end
end
