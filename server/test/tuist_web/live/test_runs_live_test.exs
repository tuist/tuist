defmodule TuistWeb.TestRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "lists latest test runs - postgres" do
    setup do
      stub(Tuist.Environment, :clickhouse_configured?, fn -> false end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> false end)
      :ok
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
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      # Then
      assert has_element?(lv, "span", "tuist test App")
      assert has_element?(lv, "span", "tuist test AppTwo")
    end
  end

  describe "lists latest test runs - clickhouse" do
    setup do
      copy(Analytics)
      stub(Tuist.Environment, :clickhouse_configured?, fn -> true end)
      stub(FunWithFlags, :enabled?, fn :clickhouse_events -> true end)

      stub(Analytics, :runs_analytics, fn _, _, _ ->
        %{runs_per_period: %{}, dates: [], values: [], count: 0, trend: 0}
      end)

      stub(Analytics, :runs_duration_analytics, fn _, _ ->
        %{dates: [], values: [], total_average_duration: 0, trend: 0}
      end)

      :ok
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
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      # Then
      assert has_element?(lv, "span", "tuist test App")
      assert has_element?(lv, "span", "tuist test AppTwo")
    end
  end
end
