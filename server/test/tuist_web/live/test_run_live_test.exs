defmodule TuistWeb.TestRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    stub(CommandEvents, :has_result_bundle?, fn _ -> false end)
    stub(Storage, :generate_download_url, fn _key, _account, _opts -> "https://s3.example.com/download" end)
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

  describe "attachments in failures" do
    test "groups attachments by repetition in the failures tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 1000,
              test_cases: [
                %{name: "testFlaky", status: "failure", duration: 500}
              ]
            }
          ]
        )

      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_failure_fixture(test_case_run_id: test_case_run.id)
      RunsFixtures.test_case_failure_fixture(test_case_run_id: test_case_run.id)

      RunsFixtures.test_case_run_repetition_fixture(
        test_case_run_id: test_case_run.id,
        repetition_number: 1,
        name: "First Run",
        status: "failure"
      )

      RunsFixtures.test_case_run_repetition_fixture(
        test_case_run_id: test_case_run.id,
        repetition_number: 2,
        name: "Retry 1",
        status: "failure"
      )

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "attempt1_screenshot.png",
        repetition_number: 1
      )

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "attempt2_screenshot.png",
        repetition_number: 2
      )

      RunsFixtures.optimize_test_case_runs()

      # When
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=failures"
        )

      # Then
      assert html =~ "attempt1_screenshot.png"
      assert html =~ "attempt2_screenshot.png"
      assert html =~ "First Run"
      assert html =~ "Retry 1"
    end

    test "shows attachment file names in the failures tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 1000,
              test_cases: [
                %{name: "testFailing", status: "failure", duration: 500}
              ]
            }
          ]
        )

      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_failure_fixture(test_case_run_id: test_case_run.id)

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "failure_screenshot.png"
      )

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "console.log"
      )

      RunsFixtures.optimize_test_case_runs()

      # When
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=failures"
        )

      # Then
      assert html =~ "failure_screenshot.png"
      assert html =~ "console.log"
    end

    test "does not show crash report attachment in attachments list on failures tab", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          test_modules: [
            %{
              name: "TestModule",
              status: "failure",
              duration: 1000,
              test_cases: [
                %{name: "testCrashing", status: "failure", duration: 500}
              ]
            }
          ]
        )

      test_run = Tuist.ClickHouseRepo.preload(test_run, :test_case_runs)
      [test_case_run | _] = test_run.test_case_runs

      RunsFixtures.test_case_failure_fixture(test_case_run_id: test_case_run.id)

      crash_attachment =
        RunsFixtures.test_case_run_attachment_fixture(
          test_case_run_id: test_case_run.id,
          file_name: "crash-report.ips"
        )

      RunsFixtures.crash_report_fixture(
        test_case_run_id: test_case_run.id,
        test_case_run_attachment_id: crash_attachment.id
      )

      RunsFixtures.test_case_run_attachment_fixture(
        test_case_run_id: test_case_run.id,
        file_name: "non_crash_screenshot.png"
      )

      RunsFixtures.optimize_test_case_runs()

      # When
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=failures"
        )

      # Then
      assert html =~ "non_crash_screenshot.png"
      assert html =~ "Crash Report"
    end
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

      # When
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      # Then - test case should NOT have "New" badge
      assert has_element?(lv, "#test-cases-table", "testExistingCase")
      refute has_element?(lv, "#test-cases-table span", "New")
    end
  end
end
