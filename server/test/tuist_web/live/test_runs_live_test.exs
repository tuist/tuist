defmodule TuistWeb.TestRunsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics

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
      alias TuistTestSupport.Fixtures.RunsFixtures

      {:ok, _test_run1} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: organization.account.id, scheme: "App")

      {:ok, _test_run2} =
        RunsFixtures.test_fixture(project_id: project.id, account_id: organization.account.id, scheme: "AppTwo")

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs")

      # Then
      assert has_element?(lv, "[data-part='test-runs-table']")
    end
  end
end
