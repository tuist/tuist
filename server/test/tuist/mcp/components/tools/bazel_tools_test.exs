defmodule Tuist.MCP.Components.Tools.BazelToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.GetBazelCacheEvent
  alias Tuist.MCP.Components.Tools.GetBazelInvocation
  alias Tuist.MCP.Components.Tools.GetBazelInvocationLog
  alias Tuist.MCP.Components.Tools.ListBazelCacheEvents
  alias Tuist.MCP.Components.Tools.ListBazelInvocationLogs
  alias Tuist.MCP.Components.Tools.ListBazelInvocations
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
    assert invocation["target_patterns"] == ["//..."]
    assert invocation["git_branch"] == "feature/bazel"
    assert invocation["git_commit_sha"] == "abcdef"
    assert invocation["is_ci"]
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

  test "lists and gets sanitized invocation logs", %{conn: conn, user: user, project: project} do
    first_id = create_invocation_log(project, "invocation-1", 10, "first")
    create_invocation_log(project, "invocation-1", 20, "second")

    result =
      ListBazelInvocationLogs.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "invocation_id" => "invocation-1"
      })

    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    assert %{"logs" => logs} = JSON.decode!(text)
    assert Enum.map(logs, & &1["message"]) == ["first", "second"]

    result =
      GetBazelInvocationLog.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "invocation_id" => "invocation-1",
        "invocation_log_id" => first_id
      })

    assert %{"content" => [%{"type" => "text", "text" => text}]} = result
    assert %{"id" => ^first_id, "message" => "first"} = JSON.decode!(text)
  end

  test "returns not found for an invalid invocation log identifier", %{conn: conn, user: user, project: project} do
    result =
      GetBazelInvocationLog.call(conn, %{
        "account_handle" => user.account.name,
        "project_handle" => project.name,
        "invocation_id" => "invocation-1",
        "invocation_log_id" => "not-a-uuid"
      })

    assert %{"isError" => true, "content" => [%{"text" => message}]} = result
    assert message =~ "Bazel invocation log not found"
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
        target_patterns: ["//..."],
        git_branch: "feature/bazel",
        git_commit_sha: "abcdef",
        is_ci: true,
        status: "success",
        exit_code: 0,
        started_at: ~N[2023-11-14 22:13:20],
        finished_at: ~N[2023-11-14 22:13:35],
        duration_ms: 15_000,
        project_id: project.id,
        account_handle: project.account.name,
        project_handle: project.name,
        cache_endpoint: "cache.tuist.dev"
      }
    ])
  end

  defp create_invocation_log(project, invocation_id, sequence_number, message) do
    id = UUIDv7.generate()

    Bazel.create_invocation_logs([
      %{
        id: id,
        invocation_id: invocation_id,
        sequence_number: sequence_number,
        stream: "stdout",
        message: message,
        project_id: project.id,
        observed_at: ~N[2026-09-04 12:00:00]
      }
    ])

    id
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
end
