defmodule TuistWeb.GenerateRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "lists latest generate runs" do
    setup do
      copy(Analytics)

      stub(Analytics, :runs_analytics, fn _, _, _ ->
        %{runs_per_period: %{}, dates: [], values: [], count: 0, trend: 0}
      end)

      stub(Analytics, :runs_duration_analytics, fn _, _ -> %{dates: [], values: []} end)
      :ok
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

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "generate",
        command_arguments: ["generate", "AppTwo"]
      )

      _generate_run_one =
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "App"]
        )

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
end
