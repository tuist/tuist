defmodule TuistWeb.GenerateRunsLiveTest do
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    FunWithFlags |> Mimic.stub(:enabled?, fn _ -> true end)
    %{conn: conn}
  end

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
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/binary-cache/generate-runs")

    # Then
    assert has_element?(lv, "span", "generate App")
    assert has_element?(lv, "span", "generate AppTwo")
  end
end
