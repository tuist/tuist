defmodule AtlasWeb.POCLive.ShowTest do
  use AtlasWeb.ConnCase, async: true

  import Atlas.POCsFixtures
  import Phoenix.LiveViewTest

  alias Atlas.Accounts.POCs

  test "renders an unpublished evaluation and its editable sections", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    poc = poc_fixture(user)
    {:ok, view, _html} = live(conn, ~p"/commercial/sales/pocs/#{poc.id}")

    assert has_element?(view, "#poc-show h1", poc.title)
    assert has_element?(view, "#poc-context-form")
    assert has_element?(view, "#poc-timeline-form")
  end

  test "renders the public link and pending access requests", %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, poc} = user |> poc_fixture() |> POCs.publish_poc(user)

    {:ok, request, _token} =
      POCs.create_access_request(poc, "visitor-#{System.unique_integer([:positive])}@example.com")

    {:ok, view, _html} = live(conn, ~p"/commercial/sales/pocs/#{poc.id}")

    assert has_element?(view, ~s(#poc-show a[href$="/p/pocs/#{poc.public_token}"]))
    assert has_element?(view, ~s(#poc-show button[phx-click="approve_access_request"][phx-value-id="#{request.id}"]))
  end
end
