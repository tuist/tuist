defmodule TuistWeb.BazelTestsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @render_async_timeout 1_000

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "bazeltests#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(name: "bazel-tests-org", creator: user, preload: [:account])

    project =
      ProjectsFixtures.project_fixture(
        name: "bazel-tests-project",
        account_id: account.id,
        build_system: :bazel,
        vcs_connection: [repository_full_handle: "tuist/bazel-telemetry-demo"]
      )

    conn =
      conn
      |> assign(:selected_project, project)
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, organization: organization, project: project}
  end

  test "renders Bazel test-target results and aligned analytics", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    create_test_result(project)

    params = %{
      "analytics-date-range" => "custom",
      "analytics-start-date" => "2000-01-01T00:00:00Z",
      "analytics-end-date" => "2100-01-01T00:00:00Z"
    }

    path = ~p"/#{organization.account.name}/#{project.name}/tests" <> "?" <> URI.encode_query(params)
    {:ok, live_view, _html} = live(conn, path)
    render_async(live_view, @render_async_timeout)

    assert has_element?(live_view, "#bazel-tests")
    assert has_element?(live_view, "#bazel-total-tests", "1")
    assert has_element?(live_view, "#bazel-test-success-rate", "100.0%")
    assert has_element?(live_view, "#bazel-tests-table", "//App:AppTests")
    assert has_element?(live_view, "#bazel-tests-table", "Flaky")
    refute has_element?(live_view, "#bazel-tests-sort-by")

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-test-duration")

    live_view
    |> element("[phx-value-widget='total-tests']")
    |> render_click()

    assert has_element?(live_view, ".tuist-widget-link[data-selected] #bazel-total-tests")
    assert has_element?(live_view, "#bazel-tests-analytics-chart")
  end

  test "renders a Bazel test-target result detail", %{
    conn: conn,
    organization: organization,
    project: project
  } do
    create_invocation(project)
    create_test_result(project)
    create_cache_event(project)
    create_invocation_logs(project)

    {test_results, _meta} = Bazel.list_test_results(project.id)
    [test_result] = test_results

    {:ok, live_view, _html} =
      live(
        conn,
        ~p"/#{organization.account.name}/#{project.name}/tests/test-results/#{test_result.id}"
      )

    assert has_element?(live_view, "#bazel-test-result", "//App:AppTests")
    assert has_element?(live_view, "#bazel-test-result", "Details")
    assert has_element?(live_view, "#bazel-test-result", "Flaky")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Attempts")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Remote services")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Mode")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Environment")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "macOS · arm64")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "Repository")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "main")
    assert has_element?(live_view, "[data-part='invocation-details-section']", "1d7b1f4f6053")
    assert has_element?(live_view, "#bazel-test-result", "Test invocation")
    assert has_element?(live_view, "#bazel-test-result", "Critical path")
    assert has_element?(live_view, "#bazel-test-result", "Metrics")
    assert has_element?(live_view, "#bazel-test-result", "Timeline")
    assert has_element?(live_view, "#bazel-build-timeline", "")
    assert has_element?(live_view, "#bazel-processor-time", "15.5s")
    assert has_element?(live_view, "[data-part='critical-path-section']", "Minimum completion time")
    assert has_element?(live_view, "[data-part='critical-path-section']", "Compiling Sources/AppTests/AppTests.swift")

    assert has_element?(
             live_view,
             "a[data-part='source-file'][href='https://github.com/tuist/bazel-telemetry-demo/blob/1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f/Sources/AppTests/AppTests.swift']"
           )

    assert has_element?(live_view, "[data-part='critical-path-timeline']")

    assert has_element?(live_view, "[data-part='tabs']", "Overview")
    assert has_element?(live_view, "[data-part='tabs']", "Command")
    assert has_element?(live_view, "[data-part='tabs']", "Cache")
    assert has_element?(live_view, "[data-part='tabs']", "Logs")
    assert has_element?(live_view, "[data-part='actions']", "Download logs")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/tests/test-results/#{test_result.id}?tab=command"
    )

    assert has_element?(live_view, "#bazel-command-configuration", "bazel test //App:AppTests")
    assert has_element?(live_view, "#bazel-command-configuration", "Bazel version")
    assert has_element?(live_view, "#bazel-requested-command-copy")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/tests/test-results/#{test_result.id}?tab=cache"
    )

    assert has_element?(live_view, "#bazel-test-result", "Summary")
    assert has_element?(live_view, "#bazel-test-cache-requests", "2")
    assert has_element?(live_view, "#bazel-test-cache-hits", "50.0%")
    assert has_element?(live_view, "#bazel-test-cache-misses", "0.0%")
    assert has_element?(live_view, "#bazel-test-cache-writes", "50.0%")
    assert has_element?(live_view, "#bazel-test-cache-events-table thead th:first-child", "Action")
    assert has_element?(live_view, "#bazel-test-cache-events-table", "SwiftCompile")
    assert has_element?(live_view, "#bazel-test-cache-events-table", "Content object")
    assert has_element?(live_view, "#bazel-test-cache-events-table", "Content-addressable storage")
    assert has_element?(live_view, "#bazel-test-cache-filter-dropdown")
    assert has_element?(live_view, "#bazel-test-cache-search")

    render_patch(
      live_view,
      ~p"/#{organization.account.name}/#{project.name}/tests/test-results/#{test_result.id}?tab=logs"
    )

    assert has_element?(live_view, "[data-part='log-output']", "Test complete")
    assert has_element?(live_view, "[data-part='back-button']", "Tests")
  end

  defp create_invocation(project) do
    finished_at = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      %{
        invocation_id: "invocation-1",
        command: "test",
        target_patterns: ["//App:AppTests"],
        bazel_version: "8.1.0",
        client_platform: "macos_arm64",
        git_branch: "main",
        git_commit_sha: "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f",
        configurations: ["ci"],
        compilation_mode: "opt",
        remote_cache_enabled: true,
        remote_execution_enabled: true,
        cpu_time_ms: 15_503,
        actions_executed: 89,
        targets_loaded: 42,
        targets_configured: 3_964,
        packages_loaded: 160,
        build_timeline_duration_ms: 8_000,
        build_timeline_lanes: ["Critical path", "Worker 1"],
        build_timeline_span_lanes: [0, 1],
        build_timeline_span_start_ms: [0, 1_000],
        build_timeline_span_durations_ms: [6_000, 2_000],
        build_timeline_span_categories: ["critical_path", "execution"],
        build_timeline_span_descriptions: [
          "action 'Compiling Sources/AppTests/AppTests.swift'",
          "Action cache check"
        ],
        status: "success",
        exit_code: 0,
        started_at: NaiveDateTime.add(finished_at, -15, :second),
        finished_at: finished_at,
        duration_ms: 15_000,
        critical_path_duration_ms: 8_000,
        critical_path_action_descriptions: [
          "action 'Compiling Sources/AppTests/AppTests.swift'",
          "action 'Testing //App:AppTests'"
        ],
        critical_path_action_durations_ms: [6_000, 2_000],
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp create_test_result(project) do
    Bazel.create_test_results([
      %{
        invocation_id: "invocation-1",
        target_label: "//App:AppTests",
        status: "flaky",
        duration_ms: 1_500,
        attempt_count: 2,
        finished_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp create_cache_event(project) do
    ReapiCache.create_cache_events([
      %{
        client_kind: "bazel",
        operation: "action_cache",
        outcome: "hit",
        action_digest: "action-hit",
        size: 2048,
        duration_ms: 10,
        invocation_id: "invocation-1",
        action_mnemonic: "SwiftCompile",
        target_label: "//App:AppTests",
        configuration_id: "config-1",
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      },
      %{
        client_kind: "bazel",
        operation: "cas",
        outcome: "write",
        action_digest: "cas-digest-1234567890",
        size: 4_096,
        duration_ms: 14,
        invocation_id: "invocation-1",
        action_mnemonic: "",
        target_label: "",
        configuration_id: "",
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp create_invocation_logs(project) do
    Bazel.create_invocation_logs([
      %{
        invocation_id: "invocation-1",
        sequence_number: 1,
        stream: "stdout",
        message: "Test complete\n",
        project_id: project.id,
        observed_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ])
  end
end
