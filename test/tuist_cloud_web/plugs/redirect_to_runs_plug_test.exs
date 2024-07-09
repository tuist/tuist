defmodule TuistCloudWeb.RedirecToRunsPlugTest do
  use TuistCloudWeb.ConnCase, async: true
  use Mimic
  alias TuistCloudWeb.RedirectToRunsPlug

  test "redirects to runs when timescale is unavailable", %{conn: conn} do
    conn = %{
      conn
      | path_params: %{"account_handle" => "owner-name", "project_handle" => "project-name"},
        path_info: ["owner-name", "project-name"]
    }

    TuistCloud.Repo |> stub(:timescale_available?, fn -> false end)

    # When
    conn = conn |> RedirectToRunsPlug.call(%{})

    # Then
    assert redirected_to(conn) == ~p"/owner-name/project-name/runs"
  end

  test "returns the same connection when timescale is available", %{conn: conn} do
    conn = %{
      conn
      | path_params: %{"account_handle" => "owner-name", "project_handle" => "project-name"},
        path_info: ["owner-name", "project-name"]
    }

    TuistCloud.Repo |> stub(:timescale_available?, fn -> true end)

    # When
    got = conn |> RedirectToRunsPlug.call(%{})

    # Then
    assert got == conn
  end

  test "returns the same connection for any path" do
    # Given
    conn = build_conn(:get, "/random-path", nil)

    # When
    got = conn |> RedirectToRunsPlug.call(%{})

    # Then
    assert got == conn
  end
end
