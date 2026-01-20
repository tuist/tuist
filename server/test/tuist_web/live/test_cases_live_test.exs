defmodule TuistWeb.TestCasesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runs.Analytics

  describe "test cases page" do
    setup do
      copy(Analytics)

      stub(Analytics, :test_case_run_analytics, fn _, _ ->
        %{dates: [], values: [], count: 0, trend: 0.0}
      end)

      stub(Analytics, :test_case_run_duration_analytics, fn _, _ ->
        %{
          dates: [],
          values: [],
          p50_values: [],
          p90_values: [],
          p99_values: [],
          total_average_duration: 0,
          p50: 0,
          p90: 0,
          p99: 0,
          trend: 0.0
        }
      end)

      :ok
    end

    test "renders test cases page with empty state", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      # Then
      assert has_element?(lv, "[data-part='test-cases']")
      assert has_element?(lv, "[data-part='empty-test-cases']")
    end

    test "lists test cases when data exists", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given - create test run with test modules/cases using the proper flow
      {:ok, _test_run} = create_test_run_with_cases(project, organization.account)

      # Wait for ClickHouse to process
      Process.sleep(100)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      # Then
      assert has_element?(lv, "[data-part='test-cases-table']")
    end

    test "shows analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      # Then
      assert has_element?(lv, "[data-part='analytics']")
      assert has_element?(lv, "[data-part='widgets']")
      assert has_element?(lv, "#widget-test-case-run-count")
      assert has_element?(lv, "#widget-failed-test-case-run-count")
      assert has_element?(lv, "#widget-test-case-run-duration")
    end

    test "supports widget selection via URL params", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When - navigate with widget selection param
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?analytics_selected_widget=failed_test_case_run_count"
        )

      # Then - verify the page loads correctly with the selected widget
      assert has_element?(lv, "[data-part='analytics']")
      assert has_element?(lv, "#widget-failed-test-case-run-count")
    end

    test "handles date range selection via URL params", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When - navigate directly with date range param
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?analytics_date_range=last_30_days")

      # Then - verify the page loads with the date range param
      assert has_element?(lv, "[data-part='analytics']")
    end

    test "handles invalid sort_by parameter gracefully", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When - navigate with an invalid sort_by parameter (ran_at instead of last_ran_at)
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?sort_by=ran_at")

      # Then - page should load successfully with default sort
      assert has_element?(lv, "[data-part='test-cases']")
    end
  end

  defp create_test_run_with_cases(project, account) do
    Tuist.Runs.create_test(%{
      id: UUIDv7.generate(),
      project_id: project.id,
      account_id: account.id,
      git_ref: "refs/heads/main",
      git_commit_sha: "abc123",
      status: "success",
      scheme: "TestScheme",
      duration: 1000,
      macos_version: "14.0",
      xcode_version: "15.0",
      is_ci: true,
      ran_at: NaiveDateTime.utc_now(),
      test_modules: [
        %{
          name: "MyTests",
          status: "success",
          duration: 100,
          test_suites: [
            %{name: "TestSuite", status: "success", duration: 100}
          ],
          test_cases: [
            %{name: "testExample", test_suite_name: "TestSuite", status: "success", duration: 100}
          ]
        }
      ]
    })
  end
end
