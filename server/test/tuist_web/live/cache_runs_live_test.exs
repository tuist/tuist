defmodule TuistWeb.CacheRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "lists latest cache runs" do
    setup do
      copy(Analytics)

      stub(Analytics, :runs_analytics, fn _, _, _ ->
        %{runs_per_period: %{}, dates: [], values: [], count: 0, trend: 0}
      end)

      stub(Analytics, :runs_duration_analytics, fn _, _ -> %{dates: [], values: []} end)
      :ok
    end

    test "lists latest cache runs", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      # Given
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "cache",
        command_arguments: ["cache", "App"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "cache",
        command_arguments: ["cache", "AppTwo"]
      )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/module-cache/cache-runs")

      # Then
      assert has_element?(lv, "span", "tuist cache App")
      assert has_element?(lv, "span", "tuist cache AppTwo")
    end
  end
end
