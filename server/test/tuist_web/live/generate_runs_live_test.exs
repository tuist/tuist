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
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs")

      # Then
      assert has_element?(lv, "span", "generate App")
      assert has_element?(lv, "span", "generate AppTwo")
    end

    test "handles cursor mismatch when sort order changes", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      for i <- 1..25 do
        CommandEventsFixtures.command_event_fixture(
          project_id: project.id,
          user_id: user.id,
          name: "generate",
          command_arguments: ["generate", "App-#{i}"],
          duration: i * 1000
        )
      end

      # Generate a cursor with created_at sorting
      {_events, %{end_cursor: cursor}} =
        Tuist.CommandEvents.list_command_events(%{
          filters: [
            %{field: :project_id, op: :==, value: project.id},
            %{field: :name, op: :in, value: ["generate"]}
          ],
          order_by: [:created_at],
          order_directions: [:desc],
          first: 20
        })

      # Navigate with duration sorting but use the cursor from created_at sorting
      # Before the fix, this would raise Flop.InvalidParamsError
      assert {:ok, lv, _html} =
               live(
                 conn,
                 ~p"/#{organization.account.name}/#{project.name}/module-cache/generate-runs?generate_runs_sort_by=duration&generate_runs_sort_order=asc&after=#{cursor}"
               )

      assert has_element?(lv, "span", "generate App-1")
    end
  end
end
