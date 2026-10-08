defmodule AtlasWeb.PageControllerTest do
  use AtlasWeb.ConnCase, async: true

  test "GET / redirects to login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/login"
    assert get_session(conn, :return_to) == nil
    assert get_resp_header(conn, "x-tuist-public") == []

    document =
      conn |> recycle() |> get(~p"/login") |> html_response(200) |> LazyHTML.from_document()

    assert Enum.count(LazyHTML.query(document, "#login")) == 1
  end

  test "GET / redirects to login when the session user no longer exists", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{"user_id" => Uniq.UUID.uuid7()})
      |> get(~p"/")

    assert redirected_to(conn) == "/login"
    assert conn.private.plug_session_info == :drop
  end

  test "protected routes preserve the destination through login", %{conn: conn} do
    conn = get(conn, ~p"/tasks?search=follow-up")
    assert redirected_to(conn) == "/login"
    assert get_session(conn, :return_to) == "/tasks?search=follow-up"
  end

  test "GET /login renders the login page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Log in to Atlas"
  end
end
