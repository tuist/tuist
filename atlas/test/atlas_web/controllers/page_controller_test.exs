defmodule AtlasWeb.PageControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Demo

  setup :verify_on_exit!

  setup do
    stub(Demo, :enabled?, fn -> false end)
    :ok
  end

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

  test "production dashboard and download routes never grant anonymous demo access", %{conn: conn} do
    for host <- ["atlas.tuist.dev", "demo.atlas.tuist.dev"],
        path <- [
          "/demo",
          "/tasks",
          "/commercial/sales/accounts",
          "/commercial/finance",
          "/commercial/finance/vendors",
          "/library/notes",
          "/library/documents",
          "/outbound/postal",
          "/operations/hardware",
          "/admin/users",
          "/admin/roles",
          "/documents/#{Uniq.UUID.uuid7()}/download"
        ] do
      response =
        conn
        |> Map.put(:host, host)
        |> put_req_header("x-atlas-demo-mode", "true")
        |> get(path)

      assert redirected_to(response) == "/login"
      assert response.assigns.current_user == nil
      assert get_resp_header(response, "x-tuist-public") == []
    end
  end

  test "GET /login renders the login page", %{conn: conn} do
    conn = get(conn, ~p"/login")
    assert html_response(conn, 200) =~ "Log in to Atlas"
  end
end
