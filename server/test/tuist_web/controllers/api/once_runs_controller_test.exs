defmodule TuistWeb.API.OnceRunsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import OpenApiSpex.TestAssertions, only: [assert_schema: 3]

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.GetOnceRun
  alias Tuist.MCP.Components.Tools.ListOnceRuns
  alias Tuist.OnceEvents
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.API.Spec
  alias TuistWeb.Authentication

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :once)
    path = "/api/projects/#{user.account.name}/#{project.name}/once/runs"
    %{conn: Authentication.put_current_user(conn, user), user: user, project: project, path: path}
  end

  describe "GET /api/projects/:account_handle/:project_handle/once/runs" do
    test "lists runs newest first, optionally of one kind", %{conn: conn, user: user, project: project, path: path} do
      build = run(project, kind: "build", started_at: ~U[2026-10-01 10:00:00.000000Z])
      test = run(project, kind: "test", started_at: ~U[2026-10-02 10:00:00.000000Z])

      in_progress =
        run(project,
          kind: "build",
          started_at: ~U[2026-10-03 10:00:00.000000Z],
          finalization: "active",
          exit_status: nil,
          finalized_at: nil
        )

      run(ProjectsFixtures.project_fixture(account_id: user.account.id), kind: "build")

      response = conn |> get(path) |> json_response(200)
      assert_schema(response, "OnceRunList", Spec.spec())
      assert Enum.map(response["runs"], & &1["run_id"]) == [in_progress, test, build]

      [active, _, finished] = response["runs"]
      assert active["status"] == "in_progress"
      assert active["finished_at"] == nil

      assert %{
               "kind" => "build",
               "command" => "once build",
               "status" => "success",
               "duration_ms" => 1200,
               "is_ci" => true,
               "git_branch" => "main",
               "git_rev" => "abc123",
               "host_class" => "macos-arm64",
               "started_at" => "2026-10-01T10:00:00Z",
               "cache" => %{"hit_rate" => 75.0, "download_bytes" => 2048, "upload_bytes" => 512}
             } = finished

      assert response["pagination_metadata"] == %{
               "has_next_page" => false,
               "has_previous_page" => false,
               "current_page" => 1,
               "page_size" => 20,
               "total_count" => 3,
               "total_pages" => 1
             }

      assert %{"runs" => [%{"run_id" => ^test}]} = conn |> get(path <> "?kind=test") |> json_response(200)
    end

    test "filters and paginates", %{conn: conn, project: project, path: path} do
      matching = run(project, exit_status: 1, git_branch: "feature", is_ci: false)
      run(project, exit_status: 0, git_branch: "feature", is_ci: false)
      run(project, exit_status: 1, git_branch: "main", is_ci: false)
      run(project, exit_status: 1, git_branch: "feature", is_ci: true)

      response =
        conn
        |> get(path <> "?kind=build&status=failure&git_branch=feature&is_ci=false")
        |> json_response(200)

      assert Enum.map(response["runs"], & &1["run_id"]) == [matching]

      page = conn |> get(path <> "?page=2&page_size=3") |> json_response(200)
      assert length(page["runs"]) == 1

      assert page["pagination_metadata"] == %{
               "has_next_page" => false,
               "has_previous_page" => true,
               "current_page" => 2,
               "page_size" => 3,
               "total_count" => 4,
               "total_pages" => 2
             }
    end

    test "counts lost runs as failures, as they are shown", %{conn: conn, project: project, path: path} do
      lost = run(project, finalization: "lost", exit_status: nil)
      failed = run(project, exit_status: 1, started_at: ~U[2026-09-30 10:00:00.000000Z])
      run(project, exit_status: 0)

      response = conn |> get(path <> "?status=failure") |> json_response(200)

      assert response["runs"] |> Enum.map(& &1["run_id"]) |> Enum.sort() == Enum.sort([lost, failed])
      assert Enum.all?(response["runs"], &(&1["status"] == "failure"))
    end

    test "returns an empty page past the last one", %{conn: conn, project: project, path: path} do
      run(project, [])

      response = conn |> get(path <> "?page=3") |> json_response(200)

      assert response["runs"] == []

      assert %{"current_page" => 3, "total_pages" => 1, "has_next_page" => false, "has_previous_page" => true} =
               response["pagination_metadata"]
    end

    test "rejects unknown kinds", %{conn: conn, path: path} do
      assert conn |> get(path <> "?kind=deploy") |> json_response(400)
    end

    test "allows an account token with project:builds:read", %{conn: conn, user: user, project: project, path: path} do
      id = run(project, [])

      response =
        conn
        |> assign(:current_subject, %AuthenticatedAccount{
          account: user.account,
          scopes: ["project:builds:read"],
          all_projects: false,
          project_ids: [project.id]
        })
        |> get(path)
        |> json_response(200)

      assert Enum.map(response["runs"], & &1["run_id"]) == [id]
    end

    test "refuses another account's private project", %{conn: conn, path: path} do
      other = AccountsFixtures.user_fixture(preload: [:account])
      assert conn |> Authentication.put_current_user(other) |> get(path) |> json_response(:forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/once/runs/:run_id" do
    test "returns a build run with action totals and the cache summary", %{conn: conn, project: project, path: path} do
      id = run(project, kind: "build")

      response = conn |> get(path <> "/" <> id) |> json_response(200)
      assert_schema(response, "OnceRunDetail", Spec.spec())

      assert response["run_id"] == id
      assert response["exit_status"] == 0
      assert response["once_version"] == "0.9.0"
      assert response["actions"] == %{"total" => 4, "cached" => 3, "executed" => 1, "failed" => 0}

      assert response["cache"] == %{
               "hits" => 3,
               "misses" => 1,
               "total_lookups" => 4,
               "hit_rate" => 75.0,
               "content_download_bytes" => 2048,
               "content_upload_bytes" => 512,
               "content_saved_bytes" => 4096
             }

      assert response["tests"] == nil
    end

    test "returns test totals for test runs", %{conn: conn, project: project, path: path} do
      id =
        run(project,
          kind: "test",
          test_case_count: 10,
          passed_test_cases: 7,
          failed_test_cases: 2,
          skipped_test_cases: 1,
          test_suite_count: 3
        )

      assert %{"tests" => %{"test_cases" => 10, "passed" => 7, "failed" => 2, "skipped" => 1, "test_suites" => 3}} =
               conn |> get(path <> "/" <> id) |> json_response(200)
    end

    test "returns 404 for unknown runs and other projects' runs", %{conn: conn, user: user, path: path} do
      other = run(ProjectsFixtures.project_fixture(account_id: user.account.id), [])

      for id <- [UUIDv7.generate(), other] do
        assert %{"message" => "Run not found."} = conn |> get(path <> "/" <> id) |> json_response(404)
      end
    end

    test "refuses another account's private project", %{conn: conn, project: project, path: path} do
      id = run(project, [])
      other = AccountsFixtures.user_fixture(preload: [:account])
      assert conn |> Authentication.put_current_user(other) |> get(path <> "/" <> id) |> json_response(:forbidden)
    end
  end

  test "the API and MCP tools return the same shapes", %{conn: conn, user: user, project: project, path: path} do
    id = run(project, kind: "test", test_case_count: 2, passed_test_cases: 2)
    args = %{"account_handle" => user.account.name, "project_handle" => project.name}
    mcp = %Plug.Conn{assigns: %{current_user: user}}

    assert %{"structuredContent" => list} = ListOnceRuns.call(mcp, args)
    assert list == conn |> get(path) |> json_response(200)

    assert %{"structuredContent" => detail} = GetOnceRun.call(mcp, Map.put(args, "run_id", id))
    assert detail == conn |> get(path <> "/" <> id) |> json_response(200)
  end

  defp run(project, attrs) do
    run_id = UUIDv7.generate()

    {:ok, _} =
      OnceEvents.upsert_run(
        Map.merge(
          %{
            project_id: project.id,
            run_id: run_id,
            kind: "build",
            once_version: "0.9.0",
            host_class: "macos-arm64",
            is_ci: true,
            git_rev: "abc123",
            git_branch: "main",
            finalization: "finalized",
            exit_status: 0,
            wall_ms: 1200,
            started_at: DateTime.utc_now(),
            finalized_at: DateTime.utc_now(),
            total_actions: 4,
            cached_actions: 3,
            executed_actions: 1,
            cache_bytes_downloaded: 2048,
            cache_bytes_uploaded: 512,
            cache_bytes_saved: 4096
          },
          Map.new(attrs)
        )
      )

    run_id
  end
end
