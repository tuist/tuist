defmodule AtlasWeb.POCLive.IndexTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.POCsFixtures
  import Phoenix.LiveViewTest

  test "renders the empty list", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/pocs")

    assert has_element?(view, "#pocs [data-part=empty-state]")
    refute has_element?(view, "#pocs-table")
  end

  test "renders an evaluation in the list", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    poc = poc_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/pocs")

    assert has_element?(view, "#pocs-table", poc.title)
  end
end
