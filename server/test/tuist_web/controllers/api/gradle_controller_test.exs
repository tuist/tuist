defmodule TuistWeb.API.GradleControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias Tuist.Gradle
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/projects/:account_handle/:project_handle/gradle/builds" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "creates a build with tasks and returns the build ID", %{conn: conn, user: user, project: project} do
      body = %{
        duration_ms: 15_000,
        status: "success",
        gradle_version: "8.5",
        java_version: "17.0.1",
        is_ci: true,
        git_branch: "main",
        git_commit_sha: "abc123",
        root_project_name: "my-app",
        tasks: [
          %{
            task_path: ":app:compileKotlin",
            task_type: "org.jetbrains.kotlin.gradle.tasks.KotlinCompile",
            outcome: "executed",
            cacheable: true,
            duration_ms: 5000,
            cache_key: "key-123"
          },
          %{
            task_path: ":app:test",
            outcome: "local_hit",
            cacheable: true,
            duration_ms: 2000
          }
        ]
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{user.account.name}/#{project.name}/gradle/builds", body)

      response = json_response(conn, 201)
      assert is_binary(response["id"])

      {:ok, build} = Gradle.get_build(response["id"])
      assert build.project_id == project.id
      assert build.duration_ms == 15_000
      assert build.status == "success"
      assert build.gradle_version == "8.5"
      assert build.is_ci == true
      assert build.tasks_executed_count == 1
      assert build.tasks_local_hit_count == 1
      assert build.cacheable_tasks_count == 2
    end

    test "creates a build with no tasks", %{conn: conn, user: user, project: project} do
      body = %{
        duration_ms: 1000,
        status: "failure",
        tasks: []
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{user.account.name}/#{project.name}/gradle/builds", body)

      response = json_response(conn, 201)
      assert is_binary(response["id"])

      {:ok, build} = Gradle.get_build(response["id"])
      assert build.status == "failure"
      assert build.cacheable_tasks_count == 0
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      body = %{duration_ms: 1000, status: "success", tasks: []}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{project.account.name}/#{project.name}/gradle/builds", body)

      assert json_response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/gradle/builds" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns an empty list when there are no builds", %{conn: conn, user: user, project: project} do
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/gradle/builds")

      response = json_response(conn, 200)
      assert response["builds"] == []
    end

    test "returns builds for the project", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          duration_ms: 12_000,
          status: "success",
          gradle_version: "8.5",
          is_ci: true,
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true},
            %{task_path: ":app:test", outcome: "local_hit", cacheable: true}
          ]
        )

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/gradle/builds")

      response = json_response(conn, 200)
      assert length(response["builds"]) == 1

      build = hd(response["builds"])
      assert build["id"] == build_id
      assert build["duration_ms"] == 12_000
      assert build["status"] == "success"
      assert build["gradle_version"] == "8.5"
      assert build["is_ci"] == true
      assert build["tasks_executed_count"] == 1
      assert build["tasks_local_hit_count"] == 1
      assert build["cacheable_tasks_count"] == 2
      assert is_number(build["cache_hit_rate"])
    end

    test "does not return builds from other projects", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      GradleFixtures.build_fixture(
        project_id: other_project.id,
        account_id: user.account.id
      )

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/gradle/builds")

      response = json_response(conn, 200)
      assert response["builds"] == []
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/gradle/builds")

      assert json_response(conn, :forbidden)
    end
  end

  describe "GET /api/projects/:account_handle/:project_handle/gradle/builds/:build_id" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      conn = Authentication.put_current_user(conn, user)

      %{conn: conn, user: user, project: project}
    end

    test "returns a build with tasks", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          duration_ms: 10_000,
          status: "success",
          gradle_version: "8.5",
          java_version: "17.0.1",
          git_branch: "main",
          git_commit_sha: "abc123",
          root_project_name: "my-app",
          tasks: [
            %{
              task_path: ":app:compileKotlin",
              task_type: "org.jetbrains.kotlin.gradle.tasks.KotlinCompile",
              outcome: "executed",
              cacheable: true,
              duration_ms: 5000,
              cache_key: "key-123"
            }
          ]
        )

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/gradle/builds/#{build_id}")

      response = json_response(conn, 200)
      assert response["id"] == build_id
      assert response["duration_ms"] == 10_000
      assert response["status"] == "success"
      assert response["gradle_version"] == "8.5"
      assert response["java_version"] == "17.0.1"
      assert response["git_branch"] == "main"
      assert response["git_commit_sha"] == "abc123"
      assert response["root_project_name"] == "my-app"

      assert length(response["tasks"]) == 1
      task = hd(response["tasks"])
      assert task["task_path"] == ":app:compileKotlin"
      assert task["outcome"] == "executed"
      assert task["cacheable"] == true
      assert task["duration_ms"] == 5000
      assert task["cache_key"] == "key-123"
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/gradle/builds/#{UUIDv7.generate()}")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      build_id =
        GradleFixtures.build_fixture(
          project_id: other_project.id,
          account_id: user.account.id
        )

      conn = get(conn, "/api/projects/#{user.account.name}/#{project.name}/gradle/builds/#{build_id}")

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn = get(conn, "/api/projects/#{project.account.name}/#{project.name}/gradle/builds/#{UUIDv7.generate()}")

      assert json_response(conn, :forbidden)
    end
  end
end
