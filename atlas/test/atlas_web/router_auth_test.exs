defmodule AtlasWeb.RouterAuthTest do
  use AtlasWeb.ConnCase, async: true

  @authenticated_paths [
    "/",
    "/sales",
    "/sales/accounts",
    "/sales/accounts/some-id",
    "/gtm/content",
    "/admin/users",
    "/mcps",
    "/mcps/grafana/authorize",
    "/mcps/grafana/callback",
    "/sessions",
    "/sessions/some-id"
  ]

  for path <- @authenticated_paths do
    test "GET #{path} redirects to /login when unauthenticated", %{conn: conn} do
      conn = get(conn, unquote(path))
      assert redirected_to(conn) == "/login"
    end
  end

  test "GET / redirects to /sales when authenticated", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    conn = get(conn, "/")
    assert redirected_to(conn) == "/sales"
  end
end
