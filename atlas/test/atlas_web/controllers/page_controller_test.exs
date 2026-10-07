defmodule AtlasWeb.PageControllerTest do
  use AtlasWeb.ConnCase, async: true

  test "GET / redirects to documentation when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/docs"
  end

  test "GET /login renders the login page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Log in to Atlas"
  end
end
