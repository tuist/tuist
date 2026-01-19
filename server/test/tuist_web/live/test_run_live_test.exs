defmodule TuistWeb.TestRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)
    %{conn: conn, user: user}
  end

  test "shows details of a test run", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    # The h1 shows the scheme name or "Unknown" if no scheme
    assert has_element?(lv, "h1")
  end

  test "shows test cases table", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    assert has_element?(lv, "[data-part='test-cases-card']")
    assert has_element?(lv, "#test-cases-table")
  end

  test "shows download button with command event ID when test run has result bundle", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    alias TuistTestSupport.Fixtures.CommandEventsFixtures
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id)

    # Create a command event associated with this test run
    command_event =
      CommandEventsFixtures.command_event_fixture(
        project_id: project.id,
        test_run_id: test_run.id,
        command_arguments: ["test", "App"]
      )

    stub(CommandEvents, :has_result_bundle?, fn _ -> true end)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    assert has_element?(lv, "a", "Download result")
    assert has_element?(lv, "a[href*='/runs/#{command_event.id}/download']")
  end

  test "hides download button when test run has no result bundle", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(project_id: project.id)

    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)

    # When
    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    refute has_element?(lv, "a", "Download result")
  end

  describe "test case badges" do
    test "shows New badge for new test cases", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_modules: [])

      test_run_id = test_run.id
      test_module_run_id = UUIDv7.generate()

      # Create a new test case run
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_run_id: test_run_id,
        test_module_run_id: test_module_run_id,
        name: "testNewCase",
        is_new: true
      )

      Process.sleep(100)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      # Then - test case should have "New" badge
      assert has_element?(lv, "#test-cases-table", "testNewCase")
      assert has_element?(lv, "#test-cases-table", "New")
    end

    test "shows Flaky badge for flaky test cases", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_modules: [])

      test_run_id = test_run.id
      test_module_run_id = UUIDv7.generate()

      # Create a flaky test case run
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_run_id: test_run_id,
        test_module_run_id: test_module_run_id,
        name: "testFlakyCase",
        is_flaky: true
      )

      Process.sleep(100)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      # Then - test case should have "Flaky" badge
      assert has_element?(lv, "#test-cases-table", "testFlakyCase")
      assert has_element?(lv, "#test-cases-table", "Flaky")
    end

    test "does not show New badge for non-new test cases", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id, test_modules: [])

      test_run_id = test_run.id
      test_module_run_id = UUIDv7.generate()

      # Create a non-new test case run
      RunsFixtures.test_case_run_fixture(
        project_id: project.id,
        test_run_id: test_run_id,
        test_module_run_id: test_module_run_id,
        name: "testExistingCase",
        is_new: false,
        is_flaky: false
      )

      Process.sleep(100)

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      # Then - test case should NOT have "New" badge
      assert has_element?(lv, "#test-cases-table", "testExistingCase")
      refute has_element?(lv, "#test-cases-table span", "New")
    end
  end
end
