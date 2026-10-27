defmodule TuistWeb.API.GradleTasksControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "GET /api/projects/:account_handle/:project_handle/builds/gradle/:build_id/tasks" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture(preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: user.account.id)
      conn = Authentication.put_current_user(conn, user)
      %{conn: conn, user: user, project: project}
    end

    test "returns tasks for the build", %{conn: conn, user: user, project: project} do
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
              duration_ms: 5000,
              cache_key: "key-123",
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

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds/gradle/#{build_id}/tasks")

      response = json_response(conn, 200)
      assert length(response["tasks"]) == 2

      first_task = hd(response["tasks"])
      assert first_task["task_path"] == ":app:compileKotlin"
      assert first_task["outcome"] == "executed"
      assert first_task["cacheable"] == true
      assert first_task["duration_ms"] == 5000

      assert %{
               "has_next_page" => false,
               "has_previous_page" => false,
               "total_count" => 2
             } = response["pagination_metadata"]
    end

    test "returns an empty list when there are no tasks", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          tasks: []
        )

      conn =
        get(conn, "/api/projects/#{user.account.name}/#{project.name}/builds/gradle/#{build_id}/tasks")

      response = json_response(conn, 200)
      assert response["tasks"] == []
    end

    test "filters tasks by outcome", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 5000},
            %{task_path: ":app:test", outcome: "local_hit", cacheable: true, duration_ms: 2000}
          ]
        )

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/builds/gradle/#{build_id}/tasks?outcome=executed"
        )

      response = json_response(conn, 200)
      assert length(response["tasks"]) == 1
      assert hd(response["tasks"])["outcome"] == "executed"
    end

    test "returns 404 when build is not found", %{conn: conn, user: user, project: project} do
      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/builds/gradle/#{UUIDv7.generate()}/tasks"
        )

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 404 when build belongs to a different project", %{conn: conn, user: user, project: project} do
      other_project = ProjectsFixtures.project_fixture(account_id: user.account.id)

      build_id =
        GradleFixtures.build_fixture(
          project_id: other_project.id,
          account_id: user.account.id,
          tasks: [%{task_path: ":app:test", outcome: "executed"}]
        )

      conn =
        get(
          conn,
          "/api/projects/#{user.account.name}/#{project.name}/builds/gradle/#{build_id}/tasks"
        )

      assert %{"message" => "Build not found."} = json_response(conn, 404)
    end

    test "returns 403 when user is not authorized", %{conn: conn, project: project} do
      other_user = AccountsFixtures.user_fixture(preload: [:account])
      conn = Authentication.put_current_user(conn, other_user)

      conn =
        get(
          conn,
          "/api/projects/#{project.account.name}/#{project.name}/builds/gradle/#{UUIDv7.generate()}/tasks"
        )

      assert json_response(conn, :forbidden)
    end
  end
end
