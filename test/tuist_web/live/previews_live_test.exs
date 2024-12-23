defmodule TuistWeb.PreviewsLiveTest do
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.PreviewsFixtures

  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  test "renders empty view when no previews are available", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given

    # When
    {:ok, _lv, html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert html =~ "No previews"
  end

  test "lists latest share previews", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview_one =
      PreviewsFixtures.preview_fixture(
        project: project,
        display_name: "AppOne",
        supported_platforms: [:ios, :macos]
      )

    _command_event_one =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview_one.id
      )

    preview_two =
      PreviewsFixtures.preview_fixture(
        project: project,
        display_name: "AppTwo",
        supported_platforms: []
      )

    _command_event_two =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview_two.id
      )

    _preview_three =
      PreviewsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios, :macos]
      )

    _command_event_three =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: nil
      )

    # When
    {:ok, lv, html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews")

    # Then
    assert html =~ "AppOne"
    assert html =~ "AppTwo"
    has_element?(lv, "span", "iOS")
    has_element?(lv, "span", "Unknown")
  end

  test "raises not found error when the project does not exist", %{conn: conn} do
    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> get(~p"/tuist/ios_app_with_frameworks/previews")
    end
  end

  test "raises not found error when the previews are not accessible by the current user", %{
    conn: conn
  } do
    # Given
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)

    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> get(~p"/#{user.account.name}/#{project.name}/previews")
    end
  end
end
