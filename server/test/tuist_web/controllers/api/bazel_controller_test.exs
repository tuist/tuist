defmodule TuistWeb.API.BazelControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Bazel
  alias Tuist.ReapiCache
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    conn = Authentication.put_current_user(conn, user)

    %{conn: conn, user: user, project: project}
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/invocations" do
    test "lists invocations with cache totals", %{conn: conn, user: user, project: project} do
      create_invocation(project, "invocation-1")
      create_cache_event(project, "invocation-1", "hit", 2048)
      create_cache_event(project, "invocation-1", "miss", 0)

      conn = get(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations")

      assert %{"invocations" => [invocation], "pagination_metadata" => _} = json_response(conn, 200)
      assert invocation["invocation_id"] == "invocation-1"
      assert invocation["command"] == "test"
      assert invocation["target_patterns"] == ["//..."]
      assert invocation["git_branch"] == "feature/bazel"
      assert invocation["git_commit_sha"] == "abcdef"
      assert invocation["is_ci"]
      assert invocation["status"] == "success"
      assert invocation["duration_ms"] == 15_000
      assert invocation["cache"]["hits"] == 1
      assert invocation["cache"]["misses"] == 1
      assert invocation["cache"]["download_bytes"] == 2048
      assert invocation["cache"]["hit_rate"] == 50.0
    end

    test "filters invocations by status", %{conn: conn, user: user, project: project} do
      create_invocation(project, "successful", status: "success", exit_code: 0)
      create_invocation(project, "failed", status: "failure", exit_code: 1)

      conn = get(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations?status=failure")

      assert %{"invocations" => [%{"invocation_id" => "failed"}]} = json_response(conn, 200)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/invocations/:invocation_id/logs" do
    test "lists invocation logs in Build Event Protocol order", %{conn: conn, user: user, project: project} do
      create_invocation_log(project, "invocation-1", 20, "second")
      create_invocation_log(project, "invocation-1", 10, "first")

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/invocation-1/logs"
        )

      assert %{"logs" => logs, "pagination_metadata" => _} = json_response(conn, 200)
      assert Enum.map(logs, & &1["sequence_number"]) == [10, 20]
      assert Enum.map(logs, & &1["message"]) == ["first", "second"]
    end

    test "gets one invocation log without crossing invocation boundaries", %{
      conn: conn,
      user: user,
      project: project
    } do
      log_id = create_invocation_log(project, "invocation-1", 10, "first")

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/invocation-1/logs/#{log_id}"
        )

      assert %{"id" => ^log_id, "message" => "first"} = json_response(conn, 200)

      conn =
        conn
        |> recycle()
        |> Authentication.put_current_user(user)
        |> get(~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/another-invocation/logs/#{log_id}")

      assert %{"message" => "Bazel invocation log not found."} = json_response(conn, 404)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/invocations/:invocation_id" do
    test "returns one invocation", %{conn: conn, user: user, project: project} do
      create_invocation(project, "invocation-1")

      conn = get(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/invocation-1")

      assert %{"invocation_id" => "invocation-1", "cache" => %{"hits" => 0}} = json_response(conn, 200)
    end

    test "returns not found for another project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
      create_invocation(other_project, "invocation-1")

      conn = get(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/invocation-1")

      assert %{"message" => "Bazel invocation not found."} = json_response(conn, 404)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/cache-events" do
    test "lists raw cache events filtered by invocation", %{conn: conn, user: user, project: project} do
      create_cache_event(project, "invocation-1", "hit", 2048)
      create_cache_event(project, "invocation-2", "write", 1024)

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/cache-events?invocation_id=invocation-1"
        )

      assert %{"cache_events" => [event], "pagination_metadata" => _} = json_response(conn, 200)
      assert event["invocation_id"] == "invocation-1"
      assert event["outcome"] == "hit"
      assert event["size"] == 2048
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/cache-events/:cache_event_id" do
    test "returns one raw cache event", %{conn: conn, user: user, project: project} do
      create_cache_event(project, "invocation-1", "hit", 2048)
      {events, _meta} = ReapiCache.list_cache_events(project.id)
      event = hd(events)

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/cache-events/#{event.id}"
        )

      assert %{"id" => event_id, "invocation_id" => "invocation-1", "outcome" => "hit"} = json_response(conn, 200)
      assert event_id == event.id
    end

    test "does not return an event from another project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
      create_cache_event(other_project, "invocation-1", "hit", 2048)
      {events, _meta} = ReapiCache.list_cache_events(other_project.id)
      event = hd(events)

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/cache-events/#{event.id}"
        )

      assert %{"message" => "Bazel remote-cache event not found."} = json_response(conn, 404)
    end
  end

  defp create_invocation(project, invocation_id, options \\ []) do
    started_at = ~N[2023-11-14 22:13:20]
    finished_at = ~N[2023-11-14 22:13:35]

    Bazel.create_invocations([
      %{
        invocation_id: invocation_id,
        command: Keyword.get(options, :command, "test"),
        target_patterns: ["//..."],
        git_branch: "feature/bazel",
        git_commit_sha: "abcdef",
        is_ci: true,
        status: Keyword.get(options, :status, "success"),
        exit_code: Keyword.get(options, :exit_code, 0),
        started_at: started_at,
        finished_at: finished_at,
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

  defp create_cache_event(project, invocation_id, outcome, size) do
    ReapiCache.create_cache_events([
      %{
        client_kind: "bazel",
        operation: "action_cache",
        outcome: outcome,
        action_digest: "digest-#{outcome}-#{size}",
        size: size,
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
