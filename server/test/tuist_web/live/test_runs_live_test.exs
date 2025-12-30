defmodule TuistWeb.TestRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics
  alias TuistTestSupport.Fixtures.RunsFixtures

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
      organization: organization,
      project: project
    } do
      # Given
      {:ok, _test_run1} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: organization.account.id, scheme: "App")

      {:ok, _test_run2} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: organization.account.id, scheme: "AppTwo")

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      # Then
      assert has_element?(lv, "[data-part='test-runs-table']")
    end

    test "handles cursor from another page with different sort fields", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      for i <- 1..25 do
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          scheme: "App-#{i}",
          duration: i * 1000
        )
      end

      # Generate a cursor with duration sorting (simulating a cursor from another page like bundles)
      {_test_runs, %{end_cursor: cursor}} =
        Tuist.Runs.list_test_runs(%{
          filters: [
            %{field: :project_id, op: :==, value: project.id}
          ],
          order_by: [:duration],
          order_directions: [:desc],
          first: 20
        })

      # Navigate to test runs with a cursor that encodes duration field
      # Test runs always sorts by created_at, so this cursor is incompatible
      # Before the fix, this would raise Flop.InvalidParamsError
      assert {:ok, lv, _html} =
               live(
                 conn,
                 ~p"/#{organization.account.name}/#{project.name}/tests/test-runs?after=#{cursor}"
               )

      # The cursor is cleared on initial load, so the page should load without error
      assert has_element?(lv, "[data-part='test-runs-table']")
    end
  end
end
