defmodule TuistWeb.TestCasesLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Tests.Analytics
  alias TuistTestSupport.Fixtures.RunsFixtures

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

      stub(Analytics, :test_cases_count_analytics, fn _, _ ->
        %{dates: [], values: [], count: 0, trend: 0.0}
      end)

      :ok
    end

    defp run_test_case(project, name, duration, git_branch) do
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: project.account_id,
        git_branch: git_branch,
        test_modules: [
          %{
            name: "DurationModule",
            status: "success",
            duration: duration,
            test_cases: [%{name: name, status: "success", duration: duration}]
          }
        ]
      )
    end

    test "renders test cases page with empty state", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      render_async(lv)

      # Then
      assert has_element?(lv, "[data-part='test-cases']")
      assert has_element?(lv, "[data-part='empty-test-cases']")
    end

    test "lists test cases when data exists", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60),
          test_modules: [
            %{
              name: "MyTests",
              status: "success",
              duration: 100,
              test_cases: [
                %{
                  name: "testExample",
                  test_suite_name: "TestSuite",
                  status: "success",
                  duration: 100
                }
              ]
            }
          ]
        )

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      render_async(lv)

      # Then
      assert has_element?(lv, "[data-part='test-cases-table']")
    end

    test "filters test cases whose module does not contain a substring", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          account_id: organization.account.id,
          ran_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -60),
          test_modules: [
            %{
              name: "ArgonUITests",
              status: "success",
              duration: 100,
              test_cases: [
                %{
                  name: "testQueued",
                  test_suite_name: "QueueSuite",
                  status: "success",
                  duration: 100
                }
              ]
            },
            %{
              name: "AppTests",
              status: "success",
              duration: 100,
              test_cases: [
                %{
                  name: "testRegular",
                  test_suite_name: "RegularSuite",
                  status: "success",
                  duration: 100
                }
              ]
            }
          ]
        )

      query =
        URI.encode_query(%{
          "filter_module_name_op" => "!=~",
          "filter_module_name_val" => "ArgonUITests"
        })

      {:ok, lv, html} =
        live(conn, "/#{organization.account.name}/#{project.name}/tests/test-cases?#{query}")

      render_async(lv)

      assert html =~ "does not contain"
      assert has_element?(lv, "[data-part='test-cases-table']", "AppTests")
      refute has_element?(lv, "[data-part='test-cases-table']", "ArgonUITests")
    end

    test "shows analytics widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      # Then
      assert has_element?(lv, "[data-part='analytics']")
      assert has_element?(lv, "[data-part='widgets']")
      assert has_element?(lv, "#widget-test-cases-count")
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
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?analytics_date_range=last_30_days"
        )

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
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?sort_by=ran_at"
        )

      # Then - page should load successfully with default sort
      assert has_element?(lv, "[data-part='test-cases']")
    end

    test "scopes the duration columns to the default branch when asked", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      for duration <- [2, 2, 2, 2, 2] do
        run_test_case(project, "testCollisions", duration, "main")
      end

      for duration <- [978, 1022, 1040, 196_101, 4_676_155] do
        run_test_case(project, "testCollisions", duration, "omarb/fix-collisions")
      end

      # When
      {:ok, any_branch, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      {:ok, default_branch, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?duration-branch=default"
        )

      # Then - the all-branches mean is dragged into the minutes by one 78-minute
      # run on a feature branch; the default-branch figure is the 2ms the test
      # actually takes.
      any_branch_html = render_async(any_branch)
      default_branch_html = render_async(default_branch)

      assert any_branch_html =~ "8m"
      assert default_branch_html =~ "2ms"
      refute default_branch_html =~ "8m"
    end

    test "says a test case has no default branch runs instead of showing every branch", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      for duration <- [900, 900, 900, 900, 4_676_155] do
        run_test_case(project, "testOnlyOnAFeatureBranch", duration, "feature")
      end

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-cases?duration-branch=default"
        )

      html = render_async(lv)

      # Then
      assert html =~ "testOnlyOnAFeatureBranch"
      assert html =~ "N/A"
      assert html =~ "on the default branch"
      refute html =~ "15m"
    end

    test "offers the branch scope alongside the table's own controls", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      render_async(lv)

      # Then
      # The dropdown's items are portaled out of the wrapper, so they are matched
      # on the rendered markup rather than as descendants of it.
      html = render(lv)

      assert has_element?(lv, "#test-cases-duration-branch")
      assert html =~ "Durations from:"
      assert html =~ ~s|href="?duration-branch=default"|
      assert html =~ "Default branch"
    end

    test "renders total test cases widget", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-cases")

      # Then
      render_async(lv)
      assert has_element?(lv, "#widget-test-cases-count")
    end
  end
end
