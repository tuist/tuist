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
        with_flushed_ingestion_buffers(fn ->
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
        end)

      _test_run_one =
        with_flushed_ingestion_buffers(fn ->
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
        end)

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
        with_flushed_ingestion_buffers(fn ->
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
        end)

      _test_run_one =
        with_flushed_ingestion_buffers(fn ->
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
        end)

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
      with_flushed_ingestion_buffers(fn ->
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
      end)

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
