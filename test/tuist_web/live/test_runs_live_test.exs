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

  test "lists latest share previews", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    _test_run_one =
      CommandEventsFixtures.command_event_fixture(
        project: project,
        name: "test",
        command_arguments: ["App"]
      )

    _test_run_one =
      CommandEventsFixtures.command_event_fixture(
        project: project,
        name: "test",
        command_arguments: ["AppTwo"]
      )

    # When
    {:ok, lv, _html} =
      conn
      |> live(~p"/#{organization.account.name}/#{project.name}/test_runs")

    # Then
    has_element?(lv, "span", "test App")
    has_element?(lv, "span", "test AppTwo")
  end
end
