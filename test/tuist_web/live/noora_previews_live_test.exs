defmodule TuistWeb.NooraPreviewsLiveTest do
  alias TuistTestSupport.Fixtures.PreviewsFixtures

  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    FunWithFlags |> Mimic.stub(:enabled?, fn _ -> true end)
    %{conn: conn}
  end

  test "renders empty view when no previews are available", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews")

    # Then
    has_element?(lv, ".tuist-empty-state")
  end

  test "lists latest share previews", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _preview_one =
      PreviewsFixtures.preview_fixture(
        project: project,
        display_name: "AppOne",
        supported_platforms: [:ios]
      )

    _preview_two =
      PreviewsFixtures.preview_fixture(
        project: project,
        display_name: "AppTwo",
        supported_platforms: []
      )

    _preview_three =
      PreviewsFixtures.preview_fixture(
        project: project,
        display_name: "App",
        supported_platforms: [:ios]
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/noora/#{organization.account.name}/#{project.name}/previews")

    # Then
    has_element?(lv, "span", "AppOne")
    has_element?(lv, "span", "AppTwo")
  end
end
