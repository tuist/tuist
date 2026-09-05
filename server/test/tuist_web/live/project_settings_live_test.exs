defmodule TuistWeb.ProjectSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  test "renders the project settings page", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    # Then
    assert html =~ "Settings"
  end

  test "handles URL parameter changes via live_patch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    # Patch the URL with query params - this triggers handle_params
    assert render_patch(lv, ~p"/#{organization.account.name}/#{project.name}/settings?tab=general") =~
             "Settings"
  end

  test "surfaces the project's default branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, _project} = Tuist.Projects.update_project(project, %{default_branch: "develop"})

    {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    assert html =~ "Default branch"
    assert html =~ "develop"
    assert has_element?(lv, "#default-branch-modal")
    assert has_element?(lv, "#default-branch-form button svg.icon-tabler-pencil")
  end

  test "updates the project's default branch", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    lv
    |> form("#default-branch-form", %{"project" => %{"default_branch" => "trunk"}})
    |> render_submit()

    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "trunk"
  end

  test "a blank default branch does not overwrite the current one", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    lv
    |> form("#default-branch-form", %{"project" => %{"default_branch" => "develop"}})
    |> render_submit()

    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "develop"

    html =
      lv
      |> form("#default-branch-form", %{"project" => %{"default_branch" => "  "}})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Tuist.Projects.get_project_by_id(project.id).default_branch == "develop"
  end

  describe "project logo" do
    test "renders the logo upload card", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

      assert html =~ "Project logo"
      assert html =~ "PNG, JPEG, or WebP"
    end

    test "uploads a logo and shows the preview", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      stub(Tuist.Storage, :put_object, fn _key, _binary, :project_logos -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

      upload =
        file_input(lv, "#upload-logo-form", :logo, [
          %{
            name: "logo.png",
            content: "png-bytes",
            type: "image/png",
            size: byte_size("png-bytes")
          }
        ])

      render_upload(upload, "logo.png")

      html =
        lv
        |> element("#upload-logo-form")
        |> render_submit()

      assert html =~ "/logo?v="
      assert Tuist.Projects.get_project_by_id(project.id).logo_storage_key
    end

    test "removes the logo", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      stub(Tuist.Storage, :put_object, fn _key, _binary, :project_logos -> :ok end)
      stub(Tuist.Storage, :delete_object, fn _key, :project_logos -> :ok end)

      {:ok, _} = Tuist.Projects.set_project_logo(project, "bytes", "image/png")

      {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")
      assert html =~ "/logo?v="

      html =
        lv
        |> element("button[phx-click=\"remove_logo\"]")
        |> render_click()

      refute html =~ "/logo?v="
      assert is_nil(Tuist.Projects.get_project_by_id(project.id).logo_storage_key)
    end
  end
end
