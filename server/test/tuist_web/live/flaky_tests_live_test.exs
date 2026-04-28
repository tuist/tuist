defmodule TuistWeb.FlakyTestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.IngestRepo
  alias Tuist.Tests.TestCase
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "flaky tests page" do
    test "renders flaky tests page with empty state", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests")

      # Then
      assert has_element?(lv, "[data-part='flaky-tests']")
      assert has_element?(lv, "[data-part='empty-flaky-tests']")
    end

    test "lists flaky tests when data exists", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      create_flaky_test_case(project, "testFlakyExample", ran_at: recent)
      RunsFixtures.optimize_test_case_runs()

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests")

      # Then
      assert has_element?(lv, "[data-part='flaky-tests-table']")
      assert has_element?(lv, "#flaky-tests-table", "testFlakyExample")
    end

    test "filters flaky tests by search term", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      create_flaky_test_case(project, "testFirstFlaky", ran_at: recent)
      create_flaky_test_case(project, "testSecondFlaky", ran_at: recent)
      RunsFixtures.optimize_test_case_runs()

      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?search=First"
        )

      # Then
      assert has_element?(lv, "#flaky-tests-table", "testFirstFlaky")
      refute has_element?(lv, "#flaky-tests-table", "testSecondFlaky")
    end

    test "supports sorting via URL params", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?sort_by=name&sort_order=asc"
        )

      # Then
      assert has_element?(lv, "[data-part='flaky-tests']")
    end

    test "handles invalid sort_by parameter gracefully", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?sort_by=invalid_field"
        )

      # Then
      assert has_element?(lv, "[data-part='flaky-tests']")
    end

    test "filters flaky tests table by environment", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      create_flaky_test_case(project, "testCIFlaky", is_ci: true, ran_at: recent)
      create_flaky_test_case(project, "testLocalFlaky", is_ci: false, ran_at: recent)
      RunsFixtures.optimize_test_case_runs()

      # When - filter by CI environment
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?analytics-environment=ci"
        )

      # Then
      assert has_element?(lv, "#flaky-tests-table", "testCIFlaky")
      refute has_element?(lv, "#flaky-tests-table", "testLocalFlaky")
    end

    test "filters flaky tests table by time range", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      create_flaky_test_case(project, "testRecentFlaky", ran_at: recent)

      old_datetime = NaiveDateTime.add(NaiveDateTime.utc_now(), -60 * 24 * 60 * 60)
      create_flaky_test_case(project, "testOldFlaky", ran_at: old_datetime)
      RunsFixtures.optimize_test_case_runs()

      # When - use default 30-day range
      {:ok, lv, _html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?analytics-date-range=last-30-days"
        )

      # Then
      assert has_element?(lv, "#flaky-tests-table", "testRecentFlaky")
      refute has_element?(lv, "#flaky-tests-table", "testOldFlaky")
    end

    test "renders flaky tests and flaky runs widgets", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      recent = NaiveDateTime.add(NaiveDateTime.utc_now(), -60)
      create_flaky_test_case(project, "testFlakyOne", ran_at: recent)
      create_flaky_test_case(project, "testFlakyTwo", ran_at: recent)
      RunsFixtures.optimize_test_case_runs()

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests")

      # Then
      render_async(lv, 2000)
      assert has_element?(lv, "#widget-flaky-tests")
      assert has_element?(lv, "#widget-flaky-runs")
    end
  end

  defp create_flaky_test_case(project, name, opts) do
    test_case = RunsFixtures.test_case_fixture(project_id: project.id, name: name, is_flaky: true)

    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

    ran_at = Keyword.get(opts, :ran_at, NaiveDateTime.add(NaiveDateTime.utc_now(), -60))

    RunsFixtures.test_case_event_fixture(
      test_case_id: test_case.id,
      event_type: "marked_flaky",
      inserted_at: ran_at
    )

    RunsFixtures.test_case_run_fixture(
      Keyword.merge(
        [project_id: project.id, test_case_id: test_case.id, is_flaky: true, ran_at: ran_at],
        opts
      )
    )

    test_case
  end
end
