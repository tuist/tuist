defmodule TuistWeb.TestRunLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.CommandEvents
  alias Tuist.IngestRepo
  alias Tuist.Runners.Job
  alias Tuist.Runners.JobSteps
  alias Tuist.Shards.Analytics, as: ShardsAnalytics
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

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

  test "surfaces linked runner CI context when test run came from a Tuist runner job", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    seed_runner_job(organization.account, 31_401, 314_010, "Run tests")

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: organization.account.id,
        scheme: "AppTests",
        duration: 95_000,
        ci_provider: "github",
        ci_run_id: "314010",
        ci_project_handle: "tuist/tuist",
        is_ci: true
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    assert has_element?(lv, "[data-part='ci-context-card']", "CI Details")
    assert has_element?(lv, "[data-part='ci-context-card'] a", "View more")

    assert has_element?(
             lv,
             ~s|[data-part='ci-context-card'] a[href="/#{organization.account.name}/runners/workflows/tuist/tuist/Server"]|,
             "Server"
           )

    assert has_element?(
             lv,
             ~s|[data-part='ci-context-card'] a[href="/#{organization.account.name}/runners/runs/314010/jobs/31401"]|,
             "Build and test"
           )

    assert has_element?(
             lv,
             ~s|[data-part='ci-context-card'] a[href="/#{organization.account.name}/runners/runs/314010/jobs/31401?tab=overview&step=2"]|,
             "Run tests ·"
           )

    refute has_element?(lv, "[data-part='ci-context-card'] a", "GitHub")
    refute has_element?(lv, "[data-part='ci-context-card']", "Status")
    refute has_element?(lv, "[data-part='ci-context-card']", "Workflow jobs")
    refute has_element?(lv, "[data-part='ci-context-card']", "Repository")
    refute has_element?(lv, "[data-part='ci-context-card']", "Run ID")
    assert render(lv) =~ "Profile"
    assert render(lv) =~ "tuist-macos"
    refute has_element?(lv, "[data-part='ci-context-card']", "Platform")
    refute has_element?(lv, "[data-part='ci-context-card']", "Test duration")
    assert has_element?(lv, "[data-part='ci-context-card']", "Step")
    assert render(lv) =~ "Run tests ·"
  end

  test "hides linked runner CI context when no runner job matches the test", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    seed_runner_job(organization.account, 31_402, 314_020, "Deploy", job_name: "Deploy")

    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        account_id: organization.account.id,
        scheme: "AppTests",
        ci_provider: "github",
        ci_run_id: "314020",
        ci_project_handle: "tuist/tuist",
        is_ci: true
      )

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    refute has_element?(lv, "[data-part='ci-context-card']")
  end

  test "renders the run destinations metadata block when destinations exist", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} =
      RunsFixtures.test_fixture(
        project_id: project.id,
        run_destinations: [
          %{name: "iPhone 17", platform: "ios_simulator", os_version: "26.4"},
          %{name: "iPhone 17 Pro", platform: "ios_simulator", os_version: "26.4"}
        ]
      )

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    assert has_element?(lv, "[data-part='run-destinations']")
    assert render(lv) =~ "iPhone 17"
    assert render(lv) =~ "iPhone 17 Pro"
    assert render(lv) =~ "iOS Simulator 26.4"
  end

  test "hides the run destinations metadata block when none were recorded", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    # Given
    {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

    # When
    {:ok, lv, _html} =
      live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

    # Then
    refute has_element?(lv, "[data-part='run-destinations']")
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
      # Then - attachments are scoped inside their repetition wrappers
      {:ok, _lv, html} =
        live(
          conn,
          ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}?tab=failures"
        )

      {:ok, document} = Floki.parse_document(html)

      repetition_wrappers =
        Floki.find(document, "[data-part=repetition-wrapper]")

      assert length(repetition_wrappers) >= 2

      # Find each wrapper by its repetition name and verify the correct attachment is inside
      first_run_wrapper =
        Enum.find(repetition_wrappers, fn w -> Floki.raw_html(w) =~ "First Run" end)

      retry_wrapper =
        Enum.find(repetition_wrappers, fn w -> Floki.raw_html(w) =~ "Retry 1" end)

      assert first_run_wrapper, "Expected a repetition wrapper for 'First Run'"
      assert retry_wrapper, "Expected a repetition wrapper for 'Retry 1'"

      first_run_html = Floki.raw_html(first_run_wrapper)
      retry_html = Floki.raw_html(retry_wrapper)

      assert first_run_html =~ "attempt1_screenshot.png"
      refute first_run_html =~ "attempt2_screenshot.png"
      assert retry_html =~ "attempt2_screenshot.png"
      refute retry_html =~ "attempt1_screenshot.png"
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

  describe "shard card for sharded test runs" do
    test "shows shard card for sharded test run", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      shard_plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 2)

      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          scheme: "AppScheme",
          shard_plan_id: shard_plan.id,
          shard_index: 0
        )

      stub(ShardsAnalytics, :shard_metrics, fn _ ->
        [
          %{shard_index: 0, actual_duration_ms: 5000, status: "success", ran_at: NaiveDateTime.utc_now()},
          %{shard_index: 1, actual_duration_ms: 4000, status: "success", ran_at: NaiveDateTime.utc_now()}
        ]
      end)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert has_element?(lv, "[data-part='shards-card']")
    end

    test "shows pending shards when not all reported", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      shard_plan = ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 3)

      {:ok, test_run} =
        RunsFixtures.test_fixture(
          project_id: project.id,
          scheme: "AppScheme",
          status: "in_progress",
          shard_plan_id: shard_plan.id,
          shard_index: 0
        )

      stub(ShardsAnalytics, :shard_metrics, fn _ ->
        [
          %{shard_index: 0, actual_duration_ms: 5000, status: "success", ran_at: NaiveDateTime.utc_now()}
        ]
      end)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert has_element?(lv, "[data-part='shards-card']")
      assert has_element?(lv, "#shard-balance-table", "Pending")
    end
  end

  describe "refresh_test_run event" do
    test "re-renders without raising when refreshing a non-processing run", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given - a finished test run rendered on the overview tab (test-cases sub-tab is the default)
      {:ok, test_run} = RunsFixtures.test_fixture(project_id: project.id)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      # When - the LiveView re-fetches the run after the run has finished processing.
      # This mirrors handle_info({:test_created, ...}) and the manual refresh flow,
      # which both reset the test_cases_meta assign back to %{}.
      html = render_hook(lv, "refresh_test_run")

      # Then - the page re-renders without raising a KeyError on @test_cases_meta.total_pages
      assert html =~ "test-cases-card"
    end
  end

  describe "transient-state polling" do
    test "clears the processing spinner once the run finishes, even without a broadcast", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given - a run still being processed, rendered live (shows the spinner)
      {:ok, test_run} =
        RunsFixtures.test_fixture(project_id: project.id, status: "processing", test_modules: [])

      {:ok, lv, html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert html =~ "processing-state"

      # When - the run finishes in ClickHouse but the completion broadcast is never
      # delivered (mirrors the cross-node-isolated xcresult-processor). The poll
      # timer firing is simulated by delivering the message directly.
      {:ok, _completed} =
        RunsFixtures.test_fixture(id: test_run.id, project_id: project.id, status: "success")

      send(lv.pid, :poll_run_state)

      # Then - the spinner clears on its own and results render
      html = render(lv)
      refute html =~ ~s(data-part="processing-state")
      assert html =~ "test-cases-card"
    end

    test "polls an in_progress (sharded) run and clears the in-progress badge on completion", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given - a run still in progress (e.g. waiting on other shards)
      {:ok, test_run} =
        RunsFixtures.test_fixture(project_id: project.id, status: "in_progress")

      {:ok, lv, html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/tests/test-runs/#{test_run.id}")

      assert html =~ ~s(data-part="badge-processing")

      # When - the run reaches a terminal status and the poll fires
      {:ok, _completed} =
        RunsFixtures.test_fixture(id: test_run.id, project_id: project.id, status: "success")

      send(lv.pid, :poll_run_state)

      # Then - the in-progress badge clears without a broadcast
      refute render(lv) =~ ~s(data-part="badge-processing")
    end
  end

  defp seed_runner_job(account, workflow_job_id, workflow_run_id, matched_step_name, opts \\ []) do
    enqueued_at = ~U[2026-05-28 10:00:00.000000Z]
    claimed_at = ~U[2026-05-28 10:00:08.000000Z]
    started_at = ~U[2026-05-28 10:00:12.000000Z]
    completed_at = ~U[2026-05-28 10:08:12.000000Z]

    IngestRepo.insert_all(Job, [
      %{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: workflow_run_id,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: Keyword.get(opts, :job_name, "Build and test"),
        head_branch: "main",
        head_sha: "abcdef1234567890",
        status: "completed",
        conclusion: "success",
        enqueued_at: enqueued_at,
        claimed_at: claimed_at,
        started_at: started_at,
        completed_at: completed_at,
        pod_name: "runner-pod-ci-context",
        runner_name: "tuist-runner-ci-context",
        requested_dispatch_label: "tuist-macos",
        updated_at: completed_at
      }
    ])

    :ok =
      JobSteps.record([
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          number: 1,
          name: "Run actions/checkout@v4",
          status: "completed",
          conclusion: "success",
          started_at: started_at,
          completed_at: DateTime.add(started_at, 20, :second)
        },
        %{
          workflow_job_id: workflow_job_id,
          account_id: account.id,
          number: 2,
          name: matched_step_name,
          status: "completed",
          conclusion: "success",
          started_at: DateTime.add(started_at, 20, :second),
          completed_at: DateTime.add(started_at, 260, :second)
        }
      ])
  end
end
