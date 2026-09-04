defmodule Tuist.MCP.Components.Tools.BazelToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.GetBazelCacheEvent
  alias Tuist.MCP.Components.Tools.GetBazelInvocation
  alias Tuist.MCP.Components.Tools.ListBazelCacheEvents
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
