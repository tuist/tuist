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
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests")

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
      create_flaky_test_case(project, "testFlakyExample")

      Process.sleep(100)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests")

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
      create_flaky_test_case(project, "testFirstFlaky")
      create_flaky_test_case(project, "testSecondFlaky")

      Process.sleep(100)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?search=First")

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
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?sort_by=name&sort_order=asc")

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
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/flaky-tests?sort_by=invalid_field")

      # Then
      assert has_element?(lv, "[data-part='flaky-tests']")
    end
  end

  defp create_flaky_test_case(project, name) do
    test_case = RunsFixtures.test_case_fixture(project_id: project.id, name: name, is_flaky: true)

    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

    test_case
  end
end
