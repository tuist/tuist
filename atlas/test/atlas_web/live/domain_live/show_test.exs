defmodule AtlasWeb.DomainLive.ShowTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Domains

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "renders a domain detail page for signed-in members", %{conn: conn} do
    {:ok, domain} =
      Domains.create_domain(%{
        "name" => "Hive",
        "description" => "Domain orchestration",
        "visibility" => "private"
      })

    {:ok, _view, html} = live(conn, ~p"/engineering/domains/#{domain.id}")

    assert html =~ "Hive"
    assert html =~ "Domain orchestration"
    assert html =~ "Save domain"
  end

  test "redirects when the domain does not exist", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/engineering/domains"}}} =
             live(conn, ~p"/engineering/domains/00000000-0000-0000-0000-000000000000")
  end

  test "updates domain fields", %{conn: conn} do
    {:ok, domain} = Domains.create_domain(%{"name" => "Atlas"})

    {:ok, view, _html} = live(conn, ~p"/engineering/domains/#{domain.id}")

    html =
      view
      |> form("#edit-domain-form",
        domain: %{
          name: "Atlas",
          description: "Planning workflows."
        }
      )
      |> render_submit()

    assert html =~ "Planning workflows."
  end

  test "domain edit form does not expose project or repository controls", %{conn: conn} do
    {:ok, domain} = Domains.create_domain(%{"name" => "Hive"})

    {:ok, view, html} = live(conn, ~p"/engineering/domains/#{domain.id}")

    assert html =~ "Save domain"
    refute has_element?(view, ~s(input[name="domain[project_id]"]))
    refute has_element?(view, ~s(input[name="domain[github_repository_owner]"]))
    refute has_element?(view, ~s(input[name="domain[github_repository_name]"]))
  end

  test "deletes a domain when the typed name matches and redirects to the index", %{conn: conn} do
    {:ok, domain} = Domains.create_domain(%{"name" => "Hive"})

    {:ok, view, html} = live(conn, ~p"/engineering/domains/#{domain.id}")
    assert html =~ "Delete domain"

    assert {:error, {:live_redirect, %{to: "/engineering/domains"}}} =
             view
             |> form("#delete-domain-form", %{"name" => "Hive"})
             |> render_submit()

    assert Domains.list_domains() == []
  end

  test "does not delete a domain when the typed name does not match", %{conn: conn} do
    {:ok, domain} = Domains.create_domain(%{"name" => "Hive"})

    {:ok, view, _html} = live(conn, ~p"/engineering/domains/#{domain.id}")

    view
    |> form("#delete-domain-form", %{"name" => "wrong"})
    |> render_submit()

    assert [%{name: "Hive"}] = Domains.list_domains()
  end
end
