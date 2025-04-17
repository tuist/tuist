defmodule TuistWeb.GenerateRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  test "lists latest generate runs", %{
    conn: conn,
    user: user,
    organization: organization,
    project: project
  } do
    # Given
    _generate_run_one =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "App"]
      )

    _generate_run_one =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "AppTwo"]
      )

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/binary-cache/generate-runs")

    # Then
    assert has_element?(lv, "span", "generate App")
    assert has_element?(lv, "span", "generate AppTwo")
  end
end
