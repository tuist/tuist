defmodule TuistWeb.QuarantinedTestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.IngestRepo
  alias Tuist.Runs.TestCase
  alias TuistTestSupport.Fixtures.RunsFixtures

  describe "quarantined tests page" do
    test "renders quarantined tests page with empty state", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/quarantined-tests")

      # Then
      assert has_element?(lv, "[data-part='quarantined-tests']")
      assert has_element?(lv, "[data-part='empty-quarantined-tests']")
    end

    test "lists quarantined tests when data exists", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      create_quarantined_test_case(project, "testQuarantinedExample")

      Process.sleep(100)

      # When
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/quarantined-tests")

      # Then
      assert has_element?(lv, "[data-part='quarantined-tests-table']")
      assert has_element?(lv, "#quarantined-tests-table", "testQuarantinedExample")
    end

    test "filters quarantined tests by search term", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      create_quarantined_test_case(project, "testFirstQuarantined")
      create_quarantined_test_case(project, "testSecondQuarantined")

      Process.sleep(100)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/quarantined-tests?search=First")

      # Then
      assert has_element?(lv, "#quarantined-tests-table", "testFirstQuarantined")
      refute has_element?(lv, "#quarantined-tests-table", "testSecondQuarantined")
    end

    test "supports sorting via URL params", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/quarantined-tests?sort_by=name&sort_order=asc")

      # Then
      assert has_element?(lv, "[data-part='quarantined-tests']")
    end

    test "handles invalid sort_by parameter gracefully", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/quarantined-tests?sort_by=invalid_field")

      # Then
      assert has_element?(lv, "[data-part='quarantined-tests']")
    end

    test "shows quarantined_by column with Tuist label for automatic quarantine", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: Create a test quarantined by Tuist (no actor)
      tuist_test_case = create_quarantined_test_case(project, "tuistQuarantinedTest")

      RunsFixtures.test_case_event_fixture(
        test_case_id: tuist_test_case.id,
        event_type: "quarantined",
        actor_id: nil
      )

      Process.sleep(100)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/quarantined-tests")

      # Then
      assert has_element?(lv, "#quarantined-tests-table", "tuistQuarantinedTest")
      assert has_element?(lv, "#quarantined-tests-table", "Tuist")
    end
  end

  defp create_quarantined_test_case(project, name) do
    test_case = RunsFixtures.test_case_fixture(project_id: project.id, name: name, is_quarantined: true)

    IngestRepo.insert_all(TestCase, [test_case |> Map.from_struct() |> Map.delete(:__meta__)])

    test_case
  end
end
