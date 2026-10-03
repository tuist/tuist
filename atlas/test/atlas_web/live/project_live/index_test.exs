defmodule AtlasWeb.ProjectLive.IndexTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Projects

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "lists projects and offers the Add project affordance", %{conn: conn} do
    {:ok, project} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, _} = Projects.create_project(%{"name" => "Tuist", "visibility" => "private"})

    {:ok, _view, html} = live(conn, ~p"/engineering/projects")

    assert html =~ "Atlas"
    assert html =~ "Tuist"
    assert html =~ ~s(/engineering/projects/#{project.id})
    assert html =~ "Add project"
  end

  test "members can create projects", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/engineering/projects")
    assert html =~ "Add project"

    html =
      render_submit(view, "create", %{
        "project" => %{
          "name" => "Noora",
          "description" => "Tuist design system.",
          "visibility" => "public"
        }
      })

    assert html =~ "Noora"
    assert html =~ "Tuist design system."
  end

  test "orders Tuist projects in the product order", %{conn: conn} do
    {:ok, atlas} = Projects.create_project(%{"name" => "Atlas", "visibility" => "public"})
    {:ok, hive} = Projects.create_project(%{"name" => "Hive", "visibility" => "public"})
    {:ok, tuist} = Projects.create_project(%{"name" => "Tuist", "visibility" => "public"})
    {:ok, kura} = Projects.create_project(%{"name" => "Kura", "visibility" => "public"})
    {:ok, noora} = Projects.create_project(%{"name" => "Noora", "visibility" => "public"})
    {:ok, once} = Projects.create_project(%{"name" => "Once", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/engineering/projects")

    assert project_position(html, atlas) < project_position(html, hive)
    assert project_position(html, hive) < project_position(html, tuist)
    assert project_position(html, tuist) < project_position(html, kura)
    assert project_position(html, kura) < project_position(html, noora)
    assert project_position(html, noora) < project_position(html, once)
  end

  test "renders the empty state when no projects exist", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/engineering/projects")

    assert html =~ "No projects yet"
  end

  defp project_position(html, project) do
    {position, _length} = :binary.match(html, ~s(/engineering/projects/#{project.id}))
    position
  end
end
