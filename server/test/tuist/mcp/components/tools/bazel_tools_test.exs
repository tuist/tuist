defmodule Tuist.MCP.Components.Tools.BazelToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.GetBazelCacheEvent
  alias Tuist.MCP.Components.Tools.GetBazelInvocation
  alias Tuist.MCP.Components.Tools.GetBazelTestResult
  alias Tuist.MCP.Components.Tools.ListBazelCacheEvents
  alias Tuist.MCP.Components.Tools.ListBazelInvocations
  alias Tuist.MCP.Components.Tools.ListBazelTestResults
  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    conn = %Plug.Conn{assigns: %{current_user: user}}

    %{conn: conn, user: user, project: project}
  end

  test "lists invocations with correlated cache totals", %{conn: conn, user: user, project: project} do
    create_invocation(project, "invocation-1")
    create_cache_event(project, "invocation-1")

    result =
      ListBazelInvocations.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name
      })

    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    assert %{"invocations" => [invocation]} = JSON.decode!(text)
    assert invocation["invocation_id"] == "invocation-1"
    assert invocation["target_patterns"] == ["//App:App"]
    assert invocation["bazel_version"] == "8.1.0"
    assert invocation["client_platform"] == "macos_arm64"
    assert invocation["configurations"] == ["ci"]
    assert invocation["compilation_mode"] == "opt"
    assert invocation["remote_cache_enabled"]
    assert invocation["remote_execution_enabled"]

    assert invocation["build_metrics"] == %{
             "cpu_time_ms" => 15_503,
             "actions_executed" => 89,
             "targets_loaded" => 42,
             "targets_configured" => 3_964,
             "packages_loaded" => 160
           }

    assert invocation["build_timeline"] == %{
             "duration_ms" => 8_000,
             "lanes" => ["Critical path", "Worker 1"],
             "spans" => [
               %{
                 "lane" => 0,
                 "start_ms" => 0,
                 "duration_ms" => 6_000,
                 "category" => "critical_path",
                 "description" => "action 'Compiling //App:App'"
               },
               %{
                 "lane" => 1,
                 "start_ms" => 1_000,
                 "duration_ms" => 2_000,
                 "category" => "execution",
                 "description" => "Action cache check"
               }
             ]
           }

    assert invocation["critical_path"] == %{
             "duration_ms" => 8_000,
             "actions" => [
               %{"description" => "action 'Compiling //App:App'", "duration_ms" => 6_000},
               %{"description" => "action 'Linking //App:App'", "duration_ms" => 2_000}
             ]
           }

    assert invocation["cache"]["hits"] == 1
    assert invocation["cache"]["invocation_id"] == nil
  end

  test "gets a Bazel invocation", %{conn: conn, user: user, project: project} do
    create_invocation(project, "invocation-1")

    result =
      GetBazelInvocation.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "invocation_id" => "invocation-1"
      })

    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    assert %{"invocation_id" => "invocation-1", "cache" => %{"hits" => 0}} = JSON.decode!(text)
  end

  test "lists and gets Bazel test-target results", %{conn: conn, user: user, project: project} do
    create_test_result(project)

    list_result =
      ListBazelTestResults.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "status" => "flaky"
      })

    assert %{"content" => [%{"type" => "text", "text" => list_text}]} = list_result

    assert %{"test_results" => [%{"target_label" => "//App:AppTests", "status" => "flaky", "id" => id}]} =
             JSON.decode!(list_text)

    get_result =
      GetBazelTestResult.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "test_result_id" => id
      })

    assert %{"content" => [%{"type" => "text", "text" => get_text}]} = get_result
    assert %{"target_label" => "//App:AppTests", "attempt_count" => 2} = JSON.decode!(get_text)
  end

  test "lists raw cache events", %{conn: conn, user: user, project: project} do
    create_cache_event(project, "invocation-1")

    result =
      ListBazelCacheEvents.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "invocation_id" => "invocation-1"
      })

    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    assert %{"cache_events" => [%{"invocation_id" => "invocation-1", "outcome" => "hit"}]} = JSON.decode!(text)
  end

  test "gets a raw cache event", %{conn: conn, user: user, project: project} do
    create_cache_event(project, "invocation-1")
    {events, _meta} = ReapiCache.list_cache_events(project.id)
    event = hd(events)

    result =
      GetBazelCacheEvent.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "cache_event_id" => event.id
      })

    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    assert %{"id" => event_id, "invocation_id" => "invocation-1"} = JSON.decode!(text)
    assert event_id == event.id
  end

  defp create_invocation(project, invocation_id) do
    Bazel.create_invocations([
      %{
        invocation_id: invocation_id,
        command: "test",
        target_patterns: ["//App:App"],
        bazel_version: "8.1.0",
        client_platform: "macos_arm64",
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
        build_timeline_span_descriptions: ["action 'Compiling //App:App'", "Action cache check"],
        status: "success",
        exit_code: 0,
        started_at: ~N[2023-11-14 22:13:20],
        finished_at: ~N[2023-11-14 22:13:35],
        duration_ms: 15_000,
        critical_path_duration_ms: 8_000,
        critical_path_action_descriptions: ["action 'Compiling //App:App'", "action 'Linking //App:App'"],
        critical_path_action_durations_ms: [6_000, 2_000],
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp create_cache_event(project, invocation_id) do
    ReapiCache.create_cache_events([
      %{
        client_kind: "bazel",
        operation: "action_cache",
        outcome: "hit",
        action_digest: "action-hit",
        size: 2048,
        duration_ms: 10,
        invocation_id: invocation_id,
        action_mnemonic: "SwiftCompile",
        target_label: "//App:App",
        configuration_id: "config-1",
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
        finished_at: ~N[2023-11-14 22:13:35],
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end
end
