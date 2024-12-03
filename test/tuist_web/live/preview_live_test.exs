defmodule TuistWeb.PreviewLiveTest do
  alias TuistWeb.Authentication
  alias Tuist.CommandEventsFixtures
  alias Tuist.PreviewsFixtures
  use TuistWeb.ConnCase, async: false
  use Tuist.LiveCase
  use Tuist.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  setup %{project: project} do
    preview = PreviewsFixtures.preview_fixture(project: project)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id
      )

    %{preview: preview}
  end

  test "it shows supported platforms", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview =
      PreviewsFixtures.preview_fixture(project: project, supported_platforms: [:ios, :macos])

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "p", "Supported platforms")
    assert has_element?(lv, "p", "iOS, macOS")
  end

  test "it does not show git branch when the associated command event does not exist", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview =
      PreviewsFixtures.preview_fixture(project: project)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "p", "Branch")
  end

  test "it does not show git branch when the git branch is nil", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = PreviewsFixtures.preview_fixture(project: project, type: :ipa)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id,
        git_branch: nil
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "p", "Branch")
  end

  test "it shows git branch when the git branch is defined", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = PreviewsFixtures.preview_fixture(project: project, type: :ipa)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id,
        git_branch: "main"
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "p", "Branch")
    assert has_element?(lv, "p", "main")
  end

  test "it shows mobile install button when family is iOS and preview_type is :ipa", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview = PreviewsFixtures.preview_fixture(project: project, type: :ipa)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id
      )

    UAParser
    |> stub(:parse, fn _ -> %UAParser.UA{os: %UAParser.OperatingSystem{family: "iOS"}} end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "button", "Run")
    assert has_element?(lv, "button", "Install")
  end

  test "it does not show install or run button when family is iOS and preview_type is :app_bundle",
       %{
         conn: conn,
         organization: organization,
         project: project
       } do
    # Given
    preview = PreviewsFixtures.preview_fixture(project: project, type: :app_bundle)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id
      )

    UAParser
    |> stub(:parse, fn _ -> %UAParser.UA{os: %UAParser.OperatingSystem{family: "iOS"}} end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "button", "Run")
    refute has_element?(lv, "button", "Install")
  end

  test "it shows desktop run button when family is iOS", %{
    conn: conn,
    organization: organization,
    project: project,
    preview: preview
  } do
    # Given
    UAParser
    |> stub(:parse, fn _ -> %UAParser.UA{os: %UAParser.OperatingSystem{family: "macOS"}} end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "button", "Run")
    refute has_element?(lv, "button", "Install")
  end

  test "it requires authenticated user when the preview is :app_bundle", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    conn
    |> Authentication.log_out_user()

    preview = PreviewsFixtures.preview_fixture(project: project, type: :app_bundle)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id
      )

    # When
    got =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert got == {:error, {:redirect, %{to: "/users/log_in", flash: %{}}}}
  end

  test "it does not require authenticated user when the preview is :ipa", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    conn
    |> Authentication.log_out_user()

    preview = PreviewsFixtures.preview_fixture(project: project, type: :ipa)

    _command_event =
      CommandEventsFixtures.command_event_fixture(
        name: "share",
        project_id: project.id,
        preview_id: preview.id
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "button", "Run")
    refute has_element?(lv, "button", "Install")
  end

  test "raises not found error when the preview does not exist", %{conn: conn} do
    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> get(~p"/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9")
    end
  end

  test "raises not found error when the preview is not accessible by the current user", %{
    conn: conn
  } do
    # Given
    preview =
      PreviewsFixtures.preview_fixture()

    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> get(~p"/tuist/ios_app_with_frameworks/previews/#{preview.id}")
    end
  end
end
