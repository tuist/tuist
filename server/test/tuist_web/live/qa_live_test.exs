defmodule TuistWeb.QALiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures

  test "renders empty state when no QA runs are available", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/qa")

    # Then
    assert has_element?(lv, "#qa-empty-state")
    refute has_element?(lv, "#qa")
  end

  test "renders normal QA view when QA runs exist", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    preview =
      AppBuildsFixtures.preview_fixture(
        project: project,
        supported_platforms: [:ios]
      )

    app_build =
      AppBuildsFixtures.app_build_fixture(
        preview: preview,
        preload: [preview: [project: :account]]
      )

    _qa_run = QAFixtures.qa_run_fixture(app_build: app_build)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/qa")

    # Then
    assert has_element?(lv, "#qa")
    refute has_element?(lv, "#qa-empty-state")
  end
end
