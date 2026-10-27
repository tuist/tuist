defmodule AtlasWeb.POCLive.FormTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.POCsFixtures
  import Phoenix.LiveViewTest

  test "renders the new evaluation form", %{conn: conn} do
    {conn, _user} = log_in_user(conn)
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/pocs/new")

    assert has_element?(view, "#poc-form-form")
  end

  test "renders the edit form with the saved title", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    poc = poc_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/pocs/#{poc.id}/edit")

    assert has_element?(view, ~s(#poc-form-form input[name="poc[title]"][value="#{poc.title}"]))
  end
end
