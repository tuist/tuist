defmodule AtlasWeb.DomainLive.IndexTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Domains

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "lists domains and offers the Add domain affordance", %{conn: conn} do
    {:ok, _domain} =
      Domains.create_domain(%{"name" => "Registry", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/engineering/domains")

    assert html =~ "Registry"
    assert html =~ "Add domain"
  end

  test "renders the empty state when there are no domains", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/engineering/domains")

    assert html =~ "Domains"
    assert html =~ "Add domain"
    assert html =~ "No domains yet"
  end

  test "renders the new domain modal", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/engineering/domains")

    assert html =~ ~s(id="new-domain-modal")
    assert html =~ "New domain"
    assert html =~ "Create a reusable domain the team can link to projects."
    assert html =~ "Name"
    assert html =~ "Description"
  end

  test "creates a reusable domain from the modal form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/engineering/domains")

    html =
      render_submit(view, "save", %{
        "domain" => %{
          "name" => "Hive",
          "description" => "Domain orchestration",
          "visibility" => "public"
        }
      })

    assert html =~ "Hive"
    assert html =~ "Domain orchestration"
  end

  test "surfaces validation errors with interpolated bindings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/engineering/domains")

    html =
      render_submit(view, "save", %{
        "domain" => %{"name" => String.duplicate("a", 121), "visibility" => "public"}
      })

    assert html =~ "should be at most 120 character(s)"
    refute html =~ "%{count}"
  end
end
