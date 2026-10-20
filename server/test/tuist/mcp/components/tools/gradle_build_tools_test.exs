defmodule Tuist.MCP.Components.Tools.GradleBuildToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Gradle.Task
  alias Tuist.IngestRepo
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

  test "private build details and tasks require the parent's project and build-read scope", %{
    user: user,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        root_project_name: "private-build-secret"
      )

    other_user = AccountsFixtures.user_fixture(preload: [:account])
    sibling = ProjectsFixtures.project_fixture(account_id: user.account.id)

    for assigns <- [
          %{},
          %{current_user: other_user},
          %{current_project: sibling},
          %{
            current_subject: %AuthenticatedAccount{
              account: user.account,
              scopes: ["project:tests:read"],
              all_projects: true
            }
          },
          %{
            current_subject: %AuthenticatedAccount{
              account: user.account,
              scopes: ["project:builds:read"],
              all_projects: false,
              project_ids: [sibling.id]
            }
          },
          %{
            current_subject: %AuthenticatedAccount{
              account: other_user.account,
              scopes: ["project:builds:read"],
              all_projects: true
            }
          }
        ],
        tool <- [GetGradleBuild, ListGradleBuildTasks] do
      result = tool.call(%Plug.Conn{assigns: assigns}, %{"build_run_id" => build_id})
      assert %{"isError" => true, "content" => [%{"text" => text}]} = result
      refute text =~ "private-build-secret"
    end
  end

  test "an authorized parent does not expose another project's tasks or cache byte totals", %{
    conn: conn,
    user: user,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        tasks: [%{task_path: ":owned:task", outcome: "remote_hit", cache_artifact_size: 1024}]
      )

    foreign = ProjectsFixtures.project_fixture()

    IngestRepo.insert_all(Task, [
      %{
        id: UUIDv7.generate(),
        project_id: foreign.id,
        gradle_build_id: build_id,
        task_path: ":foreign:secret",
        outcome: "remote_hit",
        cache_artifact_size: 999_999,
        inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
      }
    ])

    assert %{"content" => [%{"text" => tasks}]} = ListGradleBuildTasks.call(conn, %{"build_run_id" => build_id})
    assert Enum.map(JSON.decode!(tasks)["tasks"], & &1["task_path"]) == [":owned:task"]
    assert %{"content" => [%{"text" => build}]} = GetGradleBuild.call(conn, %{"build_run_id" => build_id})
    assert JSON.decode!(build)["cache_download_bytes"] == 1024
  end

  test "ID-only MCP tools refuse a public attacker's duplicate private build UUID", %{
    conn: conn,
    user: user,
    project: project
  } do
    build_id =
      GradleFixtures.build_fixture(project_id: project.id, account_id: user.account.id, root_project_name: "victim-build")

    public = ProjectsFixtures.project_fixture(visibility: :public)

    GradleFixtures.build_fixture(
      id: build_id,
      project_id: public.id,
      account_id: public.account_id,
      root_project_name: "attacker-build"
    )

    for tool <- [GetGradleBuild, ListGradleBuildTasks],
        reference <- [build_id, "https://tuist.dev/#{project.account.name}/#{project.name}/gradle/builds/#{build_id}"] do
      assert %{"isError" => true, "content" => [%{"text" => text}]} = tool.call(conn, %{"build_run_id" => reference})
      refute text =~ "attacker-build"
    end

    assert {:ok, build} = Tuist.Gradle.get_build(build_id, project_id: project.id)
    assert build.root_project_name == "victim-build"
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
        custom_tags: ["nightly"],
        custom_values: %{"team" => "android"},
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
      assert build["custom_metadata"] == %{"tags" => ["nightly"], "values" => %{"team" => "android"}}
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

    test "filters builds by custom tag", %{conn: conn, user: user, project: project} do
      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        root_project_name: "nightly-build",
        custom_tags: ["nightly"]
      )

      GradleFixtures.build_fixture(
        project_id: project.id,
        account_id: user.account.id,
        root_project_name: "release-build",
        custom_tags: ["release"]
      )

      result =
        ListGradleBuilds.call(conn, %{
          "account_handle" => user.account.name,
          "project_handle" => project.name,
          "tag" => "nightly"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert [%{"root_project_name" => "nightly-build"}] = JSON.decode!(text)["builds"]
    end
  end

  describe "get_gradle_build" do
    test "returns the remote cache transfer totals for the build", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "remote_hit", cacheable: true, cache_artifact_size: 9000},
            %{
              task_path: ":app:processResources",
              outcome: "executed",
              cacheable: true,
              cache_artifact_size: 1000,
              remote_cache_stored: true
            }
          ]
        )

      result = GetGradleBuild.call(conn, %{"build_run_id" => build_id})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert result["cache_download_bytes"] == 9000
      assert result["cache_upload_bytes"] == 1000
    end

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
          custom_tags: ["nightly"],
          custom_values: %{"team" => "android"},
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
      assert result["custom_metadata"] == %{"tags" => ["nightly"], "values" => %{"team" => "android"}}
    end

    test "returns error when build not found", %{conn: conn} do
      result = GetGradleBuild.call(conn, %{"build_run_id" => UUIDv7.generate()})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text =~ "Gradle build not found"
    end

    test "accepts a dashboard URL in place of the build ID", %{conn: conn, user: user, project: project} do
      build_id = GradleFixtures.build_fixture(project_id: project.id, account_id: user.account.id)

      result =
        GetGradleBuild.call(conn, %{
          "build_run_id" => "https://tuist.dev/#{user.account.name}/#{project.name}/gradle/builds/#{build_id}"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert JSON.decode!(text)["id"] == build_id
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

    test "lists tasks for the ID extracted from a dashboard URL", %{conn: conn, user: user, project: project} do
      build_id =
        GradleFixtures.build_fixture(
          project_id: project.id,
          account_id: user.account.id,
          tasks: [%{task_path: ":app:compileKotlin", outcome: "executed", cacheable: true, duration_ms: 12_000}]
        )

      result =
        ListGradleBuildTasks.call(conn, %{
          "build_run_id" => "https://tuist.dev/#{user.account.name}/#{project.name}/gradle/builds/#{build_id}"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert Enum.map(JSON.decode!(text)["tasks"], & &1["task_path"]) == [":app:compileKotlin"]
    end
  end
end
