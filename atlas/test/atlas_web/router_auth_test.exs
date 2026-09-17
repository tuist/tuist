defmodule AtlasWeb.RouterAuthTest do
  use AtlasWeb.ConnCase, async: true

  @authenticated_paths [
    "/",
    "/commercial/sales",
    "/commercial/sales/accounts",
    "/commercial/sales/accounts/some-id",
    "/commercial/gtm/content",
    "/admin/users",
    "/admin/mcps",
    "/mcps/grafana/authorize",
    "/mcps/grafana/callback",
    "/admin/sessions",
    "/admin/sessions/some-id"
  ]

  for path <- @authenticated_paths do
    test "GET #{path} redirects to /login when unauthenticated", %{conn: conn} do
      conn = get(conn, unquote(path))
      assert redirected_to(conn) == "/login"
    end
  end

  test "GET / redirects to /commercial/sales when authenticated", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    conn = get(conn, "/")
    assert redirected_to(conn) == "/commercial/sales"
  end
end
