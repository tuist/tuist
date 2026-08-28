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
      assert invocation["target_patterns"] == ["//App:App"]
      assert invocation["bazel_version"] == "8.1.0"
      assert invocation["client_platform"] == "macos_arm64"
      assert invocation["git_branch"] == "main"
      assert invocation["git_commit_sha"] == "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f"
      assert invocation["configurations"] == ["ci"]
      assert invocation["compilation_mode"] == "opt"
      assert invocation["remote_cache_enabled"]
      assert invocation["remote_execution_enabled"]
      assert invocation["status"] == "success"
      assert invocation["duration_ms"] == 15_000

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

  describe "POST /api/projects/:account_handle/:project_handle/bazel/invocations" do
    test "stores a completed Bazel invocation sent directly by the client", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocations",
          %{
            "invocation_id" => "direct-invocation-1",
            "command" => "build",
            "status" => "success",
            "exit_code" => 0,
            "started_at" => "2023-11-14T22:13:20Z",
            "finished_at" => "2023-11-14T22:13:35Z",
            "target_patterns" => ["//App:App"],
            "requested_command" => "bazel build --remote_header=x-api-key=do-not-store //App:App",
            "original_command_line" => [
              "bazel",
              "--client_env=TUIST_TOKEN=do-not-store",
              "--remote_header=x-api-key=do-not-store",
              "--config=ci"
            ],
            "canonical_command_line" => ["bazel", "build", "--output_base=/private/path", "//App:App"],
            "bazel_version" => "8.1.0",
            "client_platform" => "macos_arm64",
            "git_branch" => "main",
            "git_commit_sha" => "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f",
            "configurations" => ["ci"],
            "compilation_mode" => "opt",
            "remote_cache_enabled" => true,
            "remote_execution_enabled" => false,
            "build_metrics" => %{
              "cpu_time_ms" => 15_503,
              "actions_executed" => 89,
              "targets_loaded" => 42,
              "targets_configured" => 3_964,
              "packages_loaded" => 160
            },
            "build_timeline" => %{
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
            },
            "critical_path" => %{
              "duration_ms" => 8_000,
              "actions" => [
                %{"description" => "action 'Compiling //App:App'", "duration_ms" => 6_000},
                %{"description" => "action 'Linking //App:App'", "duration_ms" => 2_000}
              ]
            }
          }
        )

      assert json_response(conn, 202) == %{}
      {:ok, invocation} = Bazel.get_invocation(project.id, "direct-invocation-1")
      assert invocation.command == "build"
      assert invocation.target_patterns == ["//App:App"]
      assert invocation.requested_command == "bazel build --remote_header=<REDACTED> //App:App"
      assert invocation.original_command_line == ["bazel", "--remote_header=<REDACTED>", "--config=ci"]
      assert invocation.canonical_command_line == ["bazel", "build", "--output_base=<REDACTED>", "//App:App"]
      assert invocation.git_branch == "main"
      assert invocation.git_commit_sha == "1d7b1f4f6053e2ebc5363f531f6c9f04ab860e6f"
      assert invocation.duration_ms == 15_000
      assert invocation.client_platform == "macos_arm64"
      assert invocation.cpu_time_ms == 15_503
      assert invocation.actions_executed == 89
      assert invocation.targets_loaded == 42
      assert invocation.targets_configured == 3_964
      assert invocation.packages_loaded == 160
      assert invocation.build_timeline_duration_ms == 8_000
      assert invocation.build_timeline_lanes == ["Critical path", "Worker 1"]
      assert invocation.build_timeline_span_lanes == [0, 1]
      assert invocation.build_timeline_span_start_ms == [0, 1_000]
      assert invocation.build_timeline_span_durations_ms == [6_000, 2_000]
      assert invocation.build_timeline_span_categories == ["critical_path", "execution"]
      assert invocation.build_timeline_span_descriptions == ["action 'Compiling //App:App'", "Action cache check"]
      assert invocation.critical_path_duration_ms == 8_000

      assert invocation.critical_path_action_descriptions == [
               "action 'Compiling //App:App'",
               "action 'Linking //App:App'"
             ]

      assert invocation.critical_path_action_durations_ms == [6_000, 2_000]
      assert invocation.remote_cache_enabled
      refute invocation.remote_execution_enabled
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/bazel/invocation-logs" do
    test "stores ordered Bazel command output sent directly by the client", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocation-logs",
          %{
            "invocation_id" => "direct-invocation-1",
            "logs" => [
              %{"sequence_number" => 0, "stream" => "stdout", "message" => "Building //App:App\n"},
              %{"sequence_number" => 1, "stream" => "stderr", "message" => "warning: example\n"}
            ]
          }
        )

      assert json_response(conn, 202) == %{}

      assert [%{sequence_number: 0, stream: "stdout"}, %{sequence_number: 1, stream: "stderr"}] =
               Bazel.invocation_logs(project.id, "direct-invocation-1")
    end

    test "stores bounded Bazel invocation logs directly from the client", %{conn: conn, user: user, project: project} do
      conn =
        post(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocation-logs",
          %{
            "invocation_id" => "invocation-1",
            "logs" => [
              %{"sequence_number" => 1, "stream" => "stderr", "message" => "warning" <> <<10>>},
              %{"sequence_number" => 2, "stream" => "stdout", "message" => "Build complete" <> <<10>>}
            ]
          }
        )

      assert json_response(conn, 202) == %{}

      assert [%{stream: "stderr", message: "warning\n"}, %{stream: "stdout", message: "Build complete\n"}] =
               Bazel.invocation_logs(project.id, "invocation-1")
    end

    test "rejects oversized Bazel log chunks", %{conn: conn, user: user, project: project} do
      conn =
        post(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/invocation-logs",
          %{
            "invocation_id" => "invocation-1",
            "logs" => [
              %{"sequence_number" => 1, "stream" => "stdout", "message" => String.duplicate("x", 8 * 1024 + 1)}
            ]
          }
        )

      assert %{"message" => "Invalid Bazel invocation logs."} = json_response(conn, 400)
      assert Bazel.invocation_logs(project.id, "invocation-1") == []
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/test-results" do
    test "lists Bazel test-target results", %{conn: conn, user: user, project: project} do
      create_test_result(project, "//App:AppTests", status: "flaky")

      conn = get(conn, ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/test-results?status=flaky")

      assert %{"test_results" => [test_result], "pagination_metadata" => _} = json_response(conn, 200)
      assert test_result["target_label"] == "//App:AppTests"
      assert test_result["status"] == "flaky"
      assert test_result["duration_ms"] == 1_500
      assert test_result["attempt_count"] == 2
    end
  end

  describe "POST /api/projects/:account_handle/:project_handle/bazel/test-results" do
    test "stores final test-target results sent directly by the client", %{conn: conn, user: user, project: project} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/test-results",
          %{
            "test_results" => [
              %{
                "invocation_id" => "direct-invocation-1",
                "target_label" => "//App:AppTests",
                "status" => "flaky",
                "duration_ms" => 2_500,
                "attempt_count" => 2,
                "finished_at" => "2023-11-14T22:13:35Z"
              }
            ]
          }
        )

      assert json_response(conn, 202) == %{}
      {test_results, _meta} = Bazel.list_test_results(project.id)
      assert [%{invocation_id: "direct-invocation-1", status: "flaky", duration_ms: 2_500}] = test_results
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/bazel/test-results/:test_result_id" do
    test "returns one Bazel test-target result", %{conn: conn, user: user, project: project} do
      create_test_result(project, "//App:AppTests")
      {test_results, _meta} = Bazel.list_test_results(project.id)
      test_result = hd(test_results)

      conn =
        get(
          conn,
          ~p"/api/projects/#{user.account.name}/#{project.name}/bazel/test-results/#{test_result.id}"
        )

      assert %{"id" => id, "target_label" => "//App:AppTests"} = json_response(conn, 200)
      assert id == test_result.id
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
        target_patterns: Keyword.get(options, :target_patterns, ["//App:App"]),
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
        build_timeline_span_descriptions: ["action 'Compiling //App:App'", "Action cache check"],
        status: Keyword.get(options, :status, "success"),
        exit_code: Keyword.get(options, :exit_code, 0),
        started_at: started_at,
        finished_at: finished_at,
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

  defp create_test_result(project, target_label, options \\ []) do
    Bazel.create_test_results([
      %{
        invocation_id: Keyword.get(options, :invocation_id, "invocation-1"),
        target_label: target_label,
        status: Keyword.get(options, :status, "success"),
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
