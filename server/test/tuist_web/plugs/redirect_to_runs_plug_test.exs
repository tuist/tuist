defmodule TuistWeb.RedirecToRunsPlugTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias TuistWeb.RedirectToRunsPlug

  test "redirects to runs when timescale is unavailable", %{conn: conn} do
    conn = %{
      conn
      | path_params: %{"account_handle" => "owner-name", "project_handle" => "project-name"},
        path_info: ["owner-name", "project-name"]
    }

    stub(Tuist.Repo, :timescale_available?, fn -> false end)

    # When
    conn = RedirectToRunsPlug.call(conn, %{})

    # Then
    assert redirected_to(conn) == ~p"/owner-name/project-name/module-cache/generate-runs"
  end

  test "returns the same connection when timescale is available", %{conn: conn} do
    conn = %{
      conn
      | path_params: %{"account_handle" => "owner-name", "project_handle" => "project-name"},
        path_info: ["owner-name", "project-name"]
    }

    stub(Tuist.Repo, :timescale_available?, fn -> true end)

    # When
    got = RedirectToRunsPlug.call(conn, %{})

    # Then
    assert got == conn
  end

  test "returns the same connection for any path" do
    # Given
    conn = build_conn(:get, "/random-path", nil)

    # When
    got = RedirectToRunsPlug.call(conn, %{})

    # Then
    assert got == conn
  end
end
