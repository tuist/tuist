defmodule TuistWeb.TestRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "lists latest test runs" do
    setup do
      copy(Analytics)

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
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "App"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "AppTwo"]
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "App"]
      )

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

    test "filters test runs by status", %{
      conn: conn,
      user: user,
      organization: organization,
      project: project
    } do
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "PassingTest"],
        status: :success
      )

      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        user_id: user.id,
        name: "test",
        command_arguments: ["test", "FailingTest"],
        status: :failure
      )

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      assert has_element?(lv, "span", "tuist test PassingTest")
      assert has_element?(lv, "span", "tuist test FailingTest")

      params = %{"filter_status_op" => "==", "filter_status_val" => "0"}
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs?#{params}")

      assert has_element?(lv, "span", "tuist test PassingTest")
      refute has_element?(lv, "span", "tuist test FailingTest")

      params = %{"filter_status_op" => "==", "filter_status_val" => "1"}
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs?#{params}")

      refute has_element?(lv, "span", "tuist test PassingTest")
      assert has_element?(lv, "span", "tuist test FailingTest")
    end
  end
end
