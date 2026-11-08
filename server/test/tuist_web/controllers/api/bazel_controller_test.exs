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

      assert invocation["custom_metadata"] == %{
               "tags" => [],
               "values" => %{"environment" => "local", "runner" => "linux-arm64"}
             }

      assert invocation["bazel_version"] == "9.1.0"
      assert invocation["cache_endpoint"] == "cache.tuist.dev"
      assert invocation["status"] == "success"
      assert invocation["duration_ms"] == 15_000
      assert invocation["started_at"] == "2023-11-14T22:13:20Z"
      assert invocation["finished_at"] == "2023-11-14T22:13:35Z"
      assert invocation["build_metrics"]["actions_created"] == 11

      assert invocation["build_timeline"]["spans"] == [
               %{
                 "category" => "execution",
                 "description" => "Compile //app:app",
                 "duration_ms" => 1_000,
                 "lane" => 0,
                 "start_ms" => 500
               }
             ]

      assert invocation["critical_path"] == %{
               "actions" => [%{"description" => "Compile //app:app", "duration_ms" => 1_000}],
               "duration_ms" => 1_000
             }

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

    test "returns the latest failure on a branch and filters by commit, environment and command", %{
      conn: conn,
      user: user,
      project: project
    } do
      create_invocation(project, "main-older-failure",
        git_branch: "main",
        status: "failure",
        exit_code: 1,
        finished_at: ~N[2026-11-01 10:00:00]
      )

      create_invocation(project, "main-latest-failure",
        git_branch: "main",
        status: "failure",
        exit_code: 1,
        finished_at: ~N[2026-11-02 10:00:00],
        git_commit_sha: "c0ffee",
        is_ci: false
      )

      create_invocation(project, "main-latest-success", git_branch: "main", finished_at: ~N[2026-11-03 10:00:00])

      create_invocation(project, "other-branch-failure",
        git_branch: "feature/other",
        status: "failure",
        exit_code: 1,
        finished_at: ~N[2026-11-04 10:00:00],
        command: "build"
      )

      path = "/api/projects/#{user.account.name}/#{project.name}/bazel/invocations"

      ids = fn query ->
        conn |> get(path, query) |> json_response(200) |> Map.fetch!("invocations") |> Enum.map(& &1["invocation_id"])
      end

      assert ids.(%{status: "failure", git_branch: "main", page_size: 1}) == ["main-latest-failure"]
      assert ids.(%{git_branch: "main"}) == ["main-latest-success", "main-latest-failure", "main-older-failure"]
      assert ids.(%{git_commit_sha: "c0ffee"}) == ["main-latest-failure"]
      assert ids.(%{is_ci: false}) == ["main-latest-failure"]
      assert ids.(%{command: "build"}) == ["other-branch-failure"]
    end

    test "keeps a critical-path duration when Bazel reports no component actions", %{
      conn: conn,
      user: user,
      project: project
    } do
      create_invocation(project, "invocation-1",
        critical_path_action_descriptions: [],
        critical_path_action_durations_ms: []
      )

      conn = get(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations")

      assert %{"invocations" => [%{"critical_path" => critical_path}]} = json_response(conn, 200)
      assert critical_path == %{"actions" => [], "duration_ms" => 1_000}
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
      assert Enum.map(logs, & &1["observed_at"]) == ["2026-09-04T12:00:00Z", "2026-09-04T12:00:00Z"]
      assert Enum.map(logs, &{&1["target_label"], &1["status"]}) == [{"", ""}, {"", ""}]
    end

    test "filters invocation logs by stream, source, target, and errors", %{
      conn: conn,
      user: user,
      project: project
    } do
      create_invocation_log(
        project,
        "invocation-1",
        4,
        "INFO: Analyzed //a:a\nERROR: BUILD:3:1: Compiling a.c failed",
        "stderr"
      )

      create_invocation_log(project, "invocation-1", 5, "ERROR: printed by the program", "stdout")

      create_invocation_log(project, "invocation-1", 6, "[Bazel test log for //a:test]\nassertion", "stdout",
        target_label: "//a:test",
        status: "failure"
      )

      create_invocation_log(project, "invocation-1", 14, "[Bazel test log for //a:test]\nERROR: retried", "stdout",
        target_label: "//a:test",
        status: "success"
      )

      create_invocation_log(project, "invocation-1", 16, "[Bazel test log for //a:test_more]\nok", "stdout",
        target_label: "//a:test_more",
        status: "flaky"
      )

      create_invocation_log(project, "invocation-1", 8, "WARNING: no ERROR: at the start of a line", "stderr")
      create_invocation_log(project, "invocation-1", 10, "FAIL: //a:test (see <LOCAL_PATH>)", "stderr")
      create_invocation_log(project, "invocation-1", 12, "INFO: Build completed\n\rTIMEOUT: //b:test", "stderr")

      sequence_numbers = fn query ->
        conn
        |> recycle()
        |> Authentication.put_current_user(user)
        |> get("/api/projects/#{user.account.name}/#{project.name}/bazel/invocations/invocation-1/logs?#{query}")
        |> json_response(200)
        |> Map.fetch!("logs")
        |> Enum.map(& &1["sequence_number"])
      end

      assert sequence_numbers.("") == [4, 5, 6, 8, 10, 12, 14, 16]
      assert sequence_numbers.("stream=stderr") == [4, 8, 10, 12]
      assert sequence_numbers.("source=test_log") == [6, 14, 16]
      assert sequence_numbers.("source=progress") == [4, 5, 8, 10, 12]
      assert sequence_numbers.("target_label=//a:test") == [6, 14]
      assert sequence_numbers.("errors=true") == [4, 6, 10, 12]
      assert sequence_numbers.("errors=true&target_label=//a:test") == [6]
      assert sequence_numbers.("errors=true&page_size=1") == [4]
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

    test "filters cache events by operation and returns diagnostic context", %{
      conn: conn,
      user: user,
      project: project
    } do
      create_cache_event(project, "invocation-1", "hit", 2048)
      observed_at = ~U[2026-09-04 12:00:00.123000Z]
      create_cache_event(project, "invocation-1", "write", 1024, operation: "cas", observed_at: observed_at)

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/cache-events?operation=cas"
        )

      assert %{"cache_events" => [event], "pagination_metadata" => _} = json_response(conn, 200)
      assert event["client_kind"] == "bazel"
      assert event["operation"] == "cas"
      assert event["outcome"] == "write"
      assert event["cache_endpoint"] == "cache.tuist.dev"
      assert event["observed_at"] == "2026-09-04T12:00:00.123Z"
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
    finished_at = Keyword.get(options, :finished_at, ~N[2023-11-14 22:13:35])
    started_at = NaiveDateTime.add(finished_at, -15)

    Bazel.create_invocations([
      %{
        invocation_id: invocation_id,
        command: Keyword.get(options, :command, "test"),
        target_patterns: ["//..."],
        git_branch: Keyword.get(options, :git_branch, "feature/bazel"),
        git_commit_sha: Keyword.get(options, :git_commit_sha, "abcdef"),
        is_ci: Keyword.get(options, :is_ci, true),
        custom_values: %{"environment" => "local", "runner" => "linux-arm64"},
        bazel_version: "9.1.0",
        cpu_time_ms: 1_250,
        actions_created: 11,
        actions_executed: 10,
        targets_configured: 4,
        packages_loaded: 2,
        build_timeline_duration_ms: 15_000,
        build_timeline_lanes: ["Execution lane 1"],
        build_timeline_span_lanes: [0],
        build_timeline_span_start_ms: [500],
        build_timeline_span_durations_ms: [1_000],
        build_timeline_span_categories: ["execution"],
        build_timeline_span_descriptions: ["Compile //app:app"],
        critical_path_duration_ms: Keyword.get(options, :critical_path_duration_ms, 1_000),
        critical_path_action_descriptions:
          Keyword.get(options, :critical_path_action_descriptions, ["Compile //app:app"]),
        critical_path_action_durations_ms: Keyword.get(options, :critical_path_action_durations_ms, [1_000]),
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

  defp create_invocation_log(project, invocation_id, sequence_number, message, stream \\ "stdout", attribution \\ []) do
    id = UUIDv7.generate()

    Bazel.create_invocation_logs([
      %{
        id: id,
        invocation_id: invocation_id,
        sequence_number: sequence_number,
        stream: stream,
        message: message,
        target_label: Keyword.get(attribution, :target_label, ""),
        status: Keyword.get(attribution, :status, ""),
        project_id: project.id,
        observed_at: ~N[2026-09-04 12:00:00]
      }
    ])

    id
  end

  defp create_cache_event(project, invocation_id, outcome, size, options \\ []) do
    ReapiCache.create_cache_events([
      %{
        client_kind: "bazel",
        operation: Keyword.get(options, :operation, "action_cache"),
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
        cache_endpoint: "cache.tuist.dev",
        observed_at: Keyword.get(options, :observed_at, DateTime.utc_now())
      }
    ])
  end
end
