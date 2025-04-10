defmodule TuistWeb.NooraPreviewLiveTest do
  alias TuistWeb.Authentication
  alias TuistTestSupport.Fixtures.PreviewsFixtures
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  setup %{project: project} do
    preview = PreviewsFixtures.preview_fixture(project: project)

    FunWithFlags |> Mimic.stub(:enabled?, fn _ -> true end)

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

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, ".noora-tag span", "iOS")
    assert has_element?(lv, ".noora-tag span", "macOS")
  end

  test "it does not show run button when family is iOS and preview_type is :app_bundle",
       %{
         conn: conn,
         organization: organization,
         project: project
       } do
    # Given
    preview = PreviewsFixtures.preview_fixture(project: project, type: :app_bundle)

    UAParser
    |> stub(:parse, fn _ -> %UAParser.UA{os: %UAParser.OperatingSystem{family: "iOS"}} end)

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    refute has_element?(lv, "#preview-run-button span", "Run")
  end

  test "it shows run button when family is iOS", %{
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
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "#preview-run-button span", "Run")
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

    # When
    got =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

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

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews/#{preview.id}")

    # Then
    assert has_element?(lv, "#preview-run-button span", "Run")
  end

  test "raises not found error when the preview does not exist", %{conn: conn} do
    # When / Then
    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      conn
      |> get(
        ~p"/noora/tuist/ios_app_with_frameworks/previews/01911326-4444-771b-8dfa-7d1fc5082eb9"
      )
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
      |> get(~p"/noora/tuist/ios_app_with_frameworks/previews/#{preview.id}")
    end
  end
end
