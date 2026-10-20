defmodule AtlasWeb.ProjectLive.ShowTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Domains
  alias Atlas.Engineering.Domains.Domain
  alias Atlas.Engineering.Domains.GitHubRepository
  alias Atlas.Engineering.Projects
  alias Atlas.Repo

  setup %{conn: conn} do
    {conn, user} = log_in_user(conn)
    {:ok, conn: conn, user: user}
  end

  test "renders a project's repositories and domains", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{
        "name" => "Hive",
        "description" => "Agentic domains.",
        "visibility" => "public"
      })

    {:ok, _domain} =
      Domains.create_domain(%{
        "name" => "Hive",
        "project_id" => project.id,
        "github_repository_owner" => "tuist",
        "github_repository_name" => "hive"
      })

    {:ok, _view, html} = live(conn, ~p"/engineering/projects/#{project.id}")

    assert html =~ "Hive"
    assert html =~ "Agentic domains."
    assert html =~ "tuist/hive"
  end

  test "members can update a project", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Hive", "visibility" => "public"})

    {:ok, view, html} = live(conn, ~p"/engineering/projects/#{project.id}")

    assert html =~ "Save project"

    html =
      render_submit(view, "save", %{
        "project" => %{
          "name" => "Hive Cloud",
          "description" => "Planning and orchestration.",
          "visibility" => "private"
        }
      })

    assert html =~ "Hive Cloud"
    assert html =~ "Planning and orchestration."
  end

  test "members can set and clear the Slack alert channel", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Registry", "visibility" => "public"})

    {:ok, view, _html} = live(conn, ~p"/engineering/projects/#{project.id}")

    _ =
      render_submit(view, "save", %{
        "project" => %{
          "name" => project.name,
          "visibility" => "public",
          "slack_alert_channel" => "#alerts-registry"
        }
      })

    assert Repo.reload!(project).slack_alert_channel == "#alerts-registry"

    _ =
      render_submit(view, "save", %{
        "project" => %{
          "name" => project.name,
          "visibility" => "public",
          "slack_alert_channel" => ""
        }
      })

    assert Repo.reload!(project).slack_alert_channel == nil
  end

  test "members can delete a project after confirming its name", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Kura", "visibility" => "public"})

    {:ok, view, html} = live(conn, ~p"/engineering/projects/#{project.id}")

    assert html =~ "Delete project"

    assert {:error, {:live_redirect, %{to: "/engineering/projects"}}} =
             render_submit(view, "delete_project", %{"name" => "Kura"})
  end

  test "redirects when the project does not exist", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/engineering/projects"}}} =
             live(conn, ~p"/engineering/projects/00000000-0000-0000-0000-000000000000")
  end

  test "renders the empty state when the project has no domains", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Kura", "visibility" => "public"})

    {:ok, _view, html} = live(conn, ~p"/engineering/projects/#{project.id}")

    assert html =~ "No domains defined"
  end

  test "members can remove a repository from a project", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Hive", "visibility" => "public"})

    {:ok, _domain} =
      Domains.create_domain(%{
        "name" => "Cache",
        "project_id" => project.id,
        "github_repository_owner" => "tuist",
        "github_repository_name" => "hive"
      })

    repository = Repo.get_by!(GitHubRepository, owner: "tuist", name: "hive")

    {:ok, view, html} = live(conn, ~p"/engineering/projects/#{project.id}")
    assert html =~ "tuist/hive"
    assert html =~ "Remove repository"

    html = render_click(view, "remove_repository", %{"id" => repository.id})

    refute html =~ "tuist/hive"
    assert Repo.get(GitHubRepository, repository.id) == nil
  end

  test "members can link a repository to a project", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Hive", "visibility" => "public"})

    {:ok, view, html} = live(conn, ~p"/engineering/projects/#{project.id}")
    assert html =~ "Link repository"
    refute html =~ "tuist/hive"

    html =
      render_submit(view, "link_repository", %{
        "repository" => %{"owner" => "tuist", "name" => "hive"}
      })

    assert html =~ "tuist/hive"

    repository = Repo.get_by!(GitHubRepository, owner: "tuist", name: "hive")
    assert repository.project_id == project.id
  end

  test "members can unlink a domain from a project", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Hive", "visibility" => "public"})

    {:ok, domain} =
      Domains.create_domain(%{"name" => "Cache", "project_id" => project.id})

    {:ok, view, html} = live(conn, ~p"/engineering/projects/#{project.id}")
    assert html =~ "Cache"
    assert html =~ "Remove domain"

    html = render_click(view, "remove_domain", %{"id" => domain.id})

    refute html =~ ~s(/engineering/domains/#{domain.id})
    assert Repo.get!(Domain, domain.id)
    assert Projects.get_project!(project.id).domains == []
  end

  test "members can link an existing domain to a project", %{conn: conn} do
    {:ok, project} =
      Projects.create_project(%{"name" => "Hive", "visibility" => "public"})

    {:ok, domain} =
      Domains.create_domain(%{"name" => "Cache", "description" => "Build cache."})

    {:ok, view, html} = live(conn, ~p"/engineering/projects/#{project.id}")
    assert html =~ "Link domain"
    assert html =~ "Cache"

    html = render_submit(view, "link_domain", %{"link_domain" => %{"domain_id" => domain.id}})

    assert html =~ ~s(/engineering/domains/#{domain.id})
    assert html =~ "Build cache."
    assert Enum.map(Projects.get_project!(project.id).domains, & &1.id) == [domain.id]
  end

  # The webhook card is hidden until `Projects.ingest_webhook/4` stops
  # returning `:not_implemented`. When we bring the card back, the
  # create/delete tests move with it.
end
