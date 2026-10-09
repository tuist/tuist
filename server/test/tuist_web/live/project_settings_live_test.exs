defmodule TuistWeb.ProjectSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Projects
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

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

  test "publishing policy changes are authorized, persisted and audited", %{
    conn: conn,
    organization: organization,
    user: user
  } do
    stub(Tuist.Environment, :network_trusted_build_publishing_enabled?, fn -> true end)
    project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :gradle)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")
    assert has_element?(lv, "button[phx-click=toggle_network_trusted_builds]", "Enable publishing without credentials")

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        render_click(lv, "toggle_network_trusted_builds")
      end)

    assert Projects.get_project_by_id(project.id).network_trusted_builds
    assert has_element?(lv, "button[phx-click=toggle_network_trusted_builds]", "Disable publishing without credentials")
    assert log =~ "actor_user_id=#{user.id}"
    assert log =~ "project_id=#{project.id} enabled=true"
    log = ExUnit.CaptureLog.capture_log(fn -> render_click(lv, "toggle_network_trusted_builds") end)
    refute Projects.get_project_by_id(project.id).network_trusted_builds
    assert has_element?(lv, "button[phx-click=toggle_network_trusted_builds]", "Enable publishing without credentials")
    assert log =~ "project_id=#{project.id} enabled=false"
  end

  test "a non-administrator cannot toggle network-trusted publishing", %{conn: conn} do
    stub(Tuist.Environment, :network_trusted_build_publishing_enabled?, fn -> true end)
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: :gradle)
    user = AccountsFixtures.user_fixture()
    Tuist.Accounts.add_user_to_organization(user, organization)
    conn = log_in_user(conn, user)

    assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
      live(conn, ~p"/#{project.account.name}/#{project.name}/settings")
    end

    refute Projects.get_project_by_id(project.id).network_trusted_builds
  end

  test "unsupported projects ignore forged publishing toggle events", %{conn: conn, organization: organization} do
    stub(Tuist.Environment, :network_trusted_build_publishing_enabled?, fn -> true end)
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id, build_system: :once)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")
    render_click(lv, "toggle_network_trusted_builds")
    refute Projects.get_project_by_id(project.id).network_trusted_builds
  end

  test "deployment opt-out ignores forged publishing toggle events", %{conn: conn, organization: organization} do
    stub(Tuist.Environment, :network_trusted_build_publishing_enabled?, fn -> false end)
    project = ProjectsFixtures.project_fixture(account: organization.account, build_system: :gradle)
    {:ok, lv, _} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")
    render_click(lv, "toggle_network_trusted_builds")
    refute Projects.get_project_by_id(project.id).network_trusted_builds
  end

  test "hides bundle settings for Bazel projects", %{
    conn: conn,
    organization: organization
  } do
    project =
      ProjectsFixtures.project_fixture(
        account: organization.account,
        build_system: :bazel
      )

    {:ok, live_view, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")

    refute has_element?(live_view, "#project-settings", "Bundles")
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
    {:ok, _project} = Projects.update_project(project, %{default_branch: "develop"})

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

    assert Projects.get_project_by_id(project.id).default_branch == "trunk"
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

    assert Projects.get_project_by_id(project.id).default_branch == "develop"

    html =
      lv
      |> form("#default-branch-form", %{"project" => %{"default_branch" => "  "}})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Projects.get_project_by_id(project.id).default_branch == "develop"
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
      assert Projects.get_project_by_id(project.id).logo_storage_key
    end

    test "removes the logo", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      stub(Tuist.Storage, :put_object, fn _key, _binary, :project_logos -> :ok end)
      stub(Tuist.Storage, :delete_object, fn _key, :project_logos -> :ok end)

      {:ok, _} = Projects.set_project_logo(project, "bytes", "image/png")

      {:ok, lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings")
      assert html =~ "/logo?v="

      html =
        lv
        |> element("button[phx-click=\"remove_logo\"]")
        |> render_click()

      refute html =~ "/logo?v="
      assert is_nil(Projects.get_project_by_id(project.id).logo_storage_key)
    end
  end
end
