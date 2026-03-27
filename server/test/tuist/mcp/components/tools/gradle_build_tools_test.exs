defmodule Tuist.MCP.Components.Tools.GradleBuildToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.MCP.Components.Tools.GetGradleBuild
  alias Tuist.MCP.Components.Tools.ListGradleBuilds
  alias Tuist.MCP.Components.Tools.ListGradleBuildTasks
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id)
    conn = %Plug.Conn{assigns: %{current_user: user}}
    %{conn: conn, user: user, project: project}
  end

  describe "list_gradle_builds" do
    test "returns paginated builds", %{conn: conn, user: user, project: project} do
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        duration_ms: 45_000,
        status: "success",
        gradle_version: "8.5",
        java_version: "17.0.1",
        is_ci: true,
        git_branch: "main",
        git_commit_sha: "abc123",
        root_project_name: "my-app",
        requested_tasks: ["assembleRelease"],
        tasks: [
          %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true, duration_ms: 5000},
          %{task_path: ":app:test", outcome: "remote_hit", cacheable: true, duration_ms: 3000},
          %{task_path: ":app:lint", outcome: "executed", cacheable: true, duration_ms: 2000}
        ]
      )

      result =
        ListGradleBuilds.call(conn, %{
          "account_handle" => user.account.name,
          "project_handle" => project.name
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["builds"]) == 1
      build = hd(result["builds"])
      assert build["duration_ms"] == 45_000
      assert build["gradle_version"] == "8.5"
      assert build["status"] == "success"
    end

    test "returns error for unauthorized user", %{project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = %Plug.Conn{assigns: %{current_user: other_user}}

      result =
        ListGradleBuilds.call(conn, %{
          "account_handle" => project.account.name,
          "project_handle" => project.name
        })

      assert %{"content" => [%{"type" => "text", "text" => _text}], "isError" => true} = result
    end
  end

  describe "get_gradle_build" do
    test "returns build details", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          duration_ms: 45_000,
          status: "success",
          gradle_version: "8.5",
          java_version: "17.0.1",
          is_ci: true,
          git_branch: "main",
          git_commit_sha: "abc123",
          root_project_name: "my-app",
          requested_tasks: ["assembleRelease"],
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true, duration_ms: 5000},
            %{task_path: ":app:test", outcome: "executed", cacheable: true, duration_ms: 3000}
          ]
        )

      result = GetGradleBuild.call(conn, %{"build_run_id" => build_id})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert result["id"] == build_id
      assert result["duration_ms"] == 45_000
      assert result["gradle_version"] == "8.5"
      assert result["status"] == "success"
      assert result["tasks_local_hit_count"] == 1
      assert result["tasks_executed_count"] == 1
    end

    test "returns error when build not found", %{conn: conn} do
      result = GetGradleBuild.call(conn, %{"build_run_id" => UUIDv7.generate()})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Gradle build not found"
    end
  end

  describe "list_gradle_build_tasks" do
    test "returns build tasks", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          tasks: [
            %{
              task_path: ":app:compileKotlin",
              task_type: "KotlinCompile",
              outcome: "executed",
              cacheable: true,
              duration_ms: 12_000,
              cache_key: "key123",
              cache_artifact_size: 1024
            },
            %{
              task_path: ":app:test",
              outcome: "local_hit",
              cacheable: true,
              duration_ms: 2000
            }
          ]
        )

      result = ListGradleBuildTasks.call(conn, %{"build_run_id" => build_id})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["tasks"]) == 2
      paths = Enum.map(result["tasks"], & &1["task_path"])
      assert ":app:compileKotlin" in paths
      assert ":app:test" in paths
    end

    test "returns error when build not found", %{conn: conn} do
      result = ListGradleBuildTasks.call(conn, %{"build_run_id" => UUIDv7.generate()})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Gradle build not found"
    end
  end
end
