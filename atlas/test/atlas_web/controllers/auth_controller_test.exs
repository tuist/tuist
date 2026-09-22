defmodule AtlasWeb.AuthControllerTest do
  use AtlasWeb.ConnCase, async: true

  test "GET /auth/:provider redirects to login when the provider is not configured", %{
    conn: conn
  } do
    conn = get(conn, ~p"/auth/unknown-provider")
    assert redirected_to(conn) == "/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Authentication provider not supported."
  end
end
