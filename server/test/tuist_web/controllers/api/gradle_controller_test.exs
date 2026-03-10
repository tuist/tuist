defmodule TuistWeb.API.GradleControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Gradle
  alias Tuist.Gradle.Build.Buffer
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Authentication

  describe "POST /api/projects/:account_handle/:project_handle/gradle/builds" do
    setup %{conn: conn} do
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)
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
        requested_tasks: ["assembleDebug", "test"],
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

      Buffer.flush()
      Gradle.Task.Buffer.flush()

      {:ok, build} = Gradle.get_build(response["id"])
      assert build.project_id == project.id
      assert build.duration_ms == 15_000
      assert build.status == "success"
      assert build.gradle_version == "8.5"
      assert build.is_ci == true
      assert build.requested_tasks == ["assembleDebug", "test"]
      assert build.account_id == user.account.id
      assert build.tasks_executed_count == 1
      assert build.tasks_local_hit_count == 1
      assert build.cacheable_tasks_count == 2
    end

    test "creates a build with machine metrics", %{conn: conn, user: user, project: project} do
      body = %{
        duration_ms: 10_000,
        status: "success",
        tasks: [],
        machine_metrics: [
          %{
            timestamp: 1_741_500_001.0,
            cpu_usage_percent: 55.0,
            memory_used_bytes: 8_000_000_000,
            memory_total_bytes: 16_000_000_000,
            network_bytes_in: 1_000_000,
            network_bytes_out: 500_000,
            disk_bytes_read: 2_000_000,
            disk_bytes_written: 1_500_000
          },
          %{
            timestamp: 1_741_500_002.0,
            cpu_usage_percent: 80.0,
            memory_used_bytes: 12_000_000_000,
            memory_total_bytes: 16_000_000_000,
            network_bytes_in: 3_000_000,
            network_bytes_out: 1_500_000,
            disk_bytes_read: 5_000_000,
            disk_bytes_written: 3_000_000
          }
        ]
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{user.account.name}/#{project.name}/gradle/builds", body)

      response = json_response(conn, 201)
      assert is_binary(response["id"])

      Buffer.flush()

      build_id = response["id"]

      build =
        Tuist.ClickHouseRepo.one(from(b in Tuist.Gradle.Build, where: b.id == ^build_id))

      build = Tuist.ClickHouseRepo.preload(build, [:machine_metrics])
      assert length(build.machine_metrics) == 2
      assert_in_delta Enum.at(build.machine_metrics, 0).cpu_usage_percent, 55.0, 0.01
      assert_in_delta Enum.at(build.machine_metrics, 1).cpu_usage_percent, 80.0, 0.01
    end

    test "attributes the build to the authenticated user, not the organization", %{conn: conn} do
      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn _ -> :ok end)

      member = AccountsFixtures.user_fixture(preload: [:account])
      organization = AccountsFixtures.organization_fixture(creator: member, preload: [:account])
      project = ProjectsFixtures.project_fixture(account_id: organization.account.id)

      conn = Authentication.put_current_user(conn, member)

      body = %{
        duration_ms: 5000,
        status: "success",
        tasks: []
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{organization.account.name}/#{project.name}/gradle/builds", body)

      response = json_response(conn, 201)

      Buffer.flush()

      {:ok, build} = Gradle.get_build(response["id"])
      assert build.account_id == member.account.id
      refute build.account_id == organization.account.id
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

      Buffer.flush()

      {:ok, build} = Gradle.get_build(response["id"])
      assert build.status == "failure"
      assert build.cacheable_tasks_count == 0
    end

    test "uses client-provided build ID when present", %{conn: conn, user: user, project: project} do
      client_id = UUIDv7.generate()

      body = %{
        id: client_id,
        duration_ms: 5000,
        status: "success",
        tasks: []
      }

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/projects/#{user.account.name}/#{project.name}/gradle/builds", body)

      response = json_response(conn, 201)
      assert response["id"] == client_id

      Buffer.flush()

      {:ok, build} = Gradle.get_build(client_id)
      assert build.id == client_id
      assert build.project_id == project.id
    end

    test "enqueues a VCS pull request comment", %{conn: conn, user: user, project: project} do
      test_pid = self()

      stub(Tuist.VCS, :enqueue_vcs_pull_request_comment, fn args ->
        send(test_pid, {:vcs_comment_enqueued, args})
        :ok
      end)

      body = %{
        duration_ms: 5000,
        status: "success",
        git_commit_sha: "abc123",
        git_ref: "refs/pull/42/merge",
        git_remote_url_origin: "https://github.com/tuist/tuist.git",
        tasks: []
      }

      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/projects/#{user.account.name}/#{project.name}/gradle/builds", body)

      assert_received {:vcs_comment_enqueued, args}
      assert args.git_commit_sha == "abc123"
      assert args.git_ref == "refs/pull/42/merge"
      assert args.git_remote_url_origin == "https://github.com/tuist/tuist.git"
      assert args.project_id == project.id
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
          requested_tasks: ["assembleRelease"],
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
      assert response["requested_tasks"] == ["assembleRelease"]

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
