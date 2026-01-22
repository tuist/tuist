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

    test "ignores cursor that doesn't match order fields", %{
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

      # A cursor that was encoded with hit_rate order field
      # (decoded: {:ok, %{hit_rate: 8.5}})
      invalid_cursor = "g3QAAAABdwhoaXRfcmF0ZUZAoTAAAAAAAA=="

      # When - using the cursor with a different order field (ran_at, the default)
      # This should NOT raise an error, but ignore the invalid cursor
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/module-cache/cache-runs?before=#{invalid_cursor}"
        )

      # Then - should still render the page with results
      assert has_element?(lv, "span", "tuist cache App")
    end

    test "filters cache runs by user with ran_by filter", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      other_user = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture()
      :ok = Tuist.Accounts.add_user_to_organization(other_user, organization)

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "cache",
        command_arguments: ["cache", "UserApp"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: other_user.id,
        name: "cache",
        command_arguments: ["cache", "OtherUserApp"]
      )

      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/module-cache/cache-runs?filter_ran_by_op===&filter_ran_by_val=#{user.id}"
        )

      assert has_element?(lv, "span", "tuist cache UserApp")
      refute has_element?(lv, "span", "tuist cache OtherUserApp")
    end
  end
end
