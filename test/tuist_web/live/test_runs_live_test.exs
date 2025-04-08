defmodule TuistWeb.TestRunsLiveTest do
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

  test "lists latest test runs", %{
    conn: conn,
    user: user,
    organization: organization,
    project: project
  } do
    # Given
    _test_run_one =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "App"]
      )

    _test_run_one =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "AppTwo"]
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/test_runs")

    # Then
    assert has_element?(lv, "span", "tuist test App")
    assert has_element?(lv, "span", "tuist test AppTwo")
  end
end
