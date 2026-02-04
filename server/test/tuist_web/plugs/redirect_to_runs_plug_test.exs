defmodule TuistWeb.RedirecToRunsPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias TuistWeb.RedirectToRunsPlug

  test "returns the same connection (plug is now a no-op)", %{conn: conn} do
    conn = %{
      conn
      | path_params: %{"account_handle" => "owner-name", "project_handle" => "project-name"},
        path_info: ["owner-name", "project-name"]
    }

    got = RedirectToRunsPlug.call(conn, %{})

    assert got == conn
  end

  test "returns the same connection for any path" do
    conn = build_conn(:get, "/random-path", nil)

    got = RedirectToRunsPlug.call(conn, %{})

    assert got == conn
  end
end
