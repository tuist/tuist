defmodule Tuist.MCP.Components.Tools.GradleBuildToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Gradle
  alias Tuist.MCP.Components.Tools.GetGradleBuild
  alias Tuist.MCP.Components.Tools.ListGradleBuilds
  alias Tuist.MCP.Components.Tools.ListGradleBuildTasks
  alias Tuist.Projects

  defp conn_with_subject do
    %Plug.Conn{assigns: %{current_subject: :subject}}
  end

  defp pagination_meta(overrides \\ %{}) do
    Map.merge(
      %{
        has_next_page?: false,
        has_previous_page?: false,
        total_count: 1,
        total_pages: 1,
        current_page: 1,
        page_size: 20
      },
      overrides
    )
  end

  describe "list_gradle_builds" do
    test "returns paginated builds" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Gradle, :list_builds, fn _project_id, _attrs ->
        {[
           %{
             id: "gradle-build-1",
             duration_ms: 45_000,
             status: "success",
             gradle_version: "8.5",
             java_version: "17.0.1",
             is_ci: true,
             git_branch: "main",
             git_commit_sha: "abc123",
             root_project_name: "my-app",
             requested_tasks: ["assembleRelease"],
             tasks_local_hit_count: 5,
             tasks_remote_hit_count: 3,
             tasks_executed_count: 2,
             cacheable_tasks_count: 10,
             inserted_at: ~N[2024-01-01 12:00:00]
           }
         ], pagination_meta()}
      end)

      result =
        ListGradleBuilds.call(conn_with_subject(), %{
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["builds"]) == 1
      build = hd(result["builds"])
      assert build["id"] == "gradle-build-1"
      assert build["duration_ms"] == 45_000
      assert build["gradle_version"] == "8.5"
      assert build["cache_hit_rate"] == 80.0
    end

    test "requires :build_read authorization" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      result =
        ListGradleBuilds.call(conn_with_subject(), %{
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text == "You do not have access to project: acme/app"
    end
  end

  describe "get_gradle_build" do
    test "returns build details" do
      project = %{id: 1, name: "app"}

      stub(Gradle, :get_build, fn "gradle-build-1" ->
        {:ok,
         %{
           id: "gradle-build-1",
           duration_ms: 45_000,
           status: "success",
           gradle_version: "8.5",
           java_version: "17.0.1",
           is_ci: true,
           git_branch: "main",
           git_commit_sha: "abc123",
           git_ref: "refs/heads/main",
           root_project_name: "my-app",
           requested_tasks: ["assembleRelease"],
           tasks_local_hit_count: 5,
           tasks_remote_hit_count: 3,
           tasks_up_to_date_count: 10,
           tasks_executed_count: 2,
           tasks_failed_count: 0,
           tasks_skipped_count: 1,
           tasks_no_source_count: 0,
           cacheable_tasks_count: 10,
           project_id: 1,
           inserted_at: ~N[2024-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      result = GetGradleBuild.call(conn_with_subject(), %{"build_run_id" => "gradle-build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert result["id"] == "gradle-build-1"
      assert result["duration_ms"] == 45_000
      assert result["gradle_version"] == "8.5"
      assert result["tasks_up_to_date_count"] == 10
      assert result["cache_hit_rate"] == 80.0
    end

    test "returns error when build not found" do
      stub(Gradle, :get_build, fn "nonexistent" -> {:error, :not_found} end)

      result = GetGradleBuild.call(conn_with_subject(), %{"build_run_id" => "nonexistent"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text == "Gradle build not found: nonexistent"
    end
  end

  describe "list_gradle_build_tasks" do
    test "returns build tasks" do
      project = %{id: 1, name: "app"}

      stub(Gradle, :get_build, fn "gradle-build-1" ->
        {:ok, %{id: "gradle-build-1", project_id: 1}}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Gradle, :list_tasks, fn _build_id, _attrs ->
        {[
           %{
             id: "task-1",
             task_path: ":app:compileKotlin",
             task_type: "KotlinCompile",
             outcome: "executed",
             cacheable: true,
             duration_ms: 12_000,
             cache_key: "key123",
             cache_artifact_size: 1024,
             started_at: ~N[2024-01-01 12:00:05]
           }
         ], pagination_meta()}
      end)

      result =
        ListGradleBuildTasks.call(conn_with_subject(), %{"build_run_id" => "gradle-build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["tasks"]) == 1
      task = hd(result["tasks"])
      assert task["task_path"] == ":app:compileKotlin"
      assert task["outcome"] == "executed"
      assert task["cacheable"] == true
      assert task["duration_ms"] == 12_000
    end

    test "returns error when build not found" do
      stub(Gradle, :get_build, fn "nonexistent" -> {:error, :not_found} end)

      result =
        ListGradleBuildTasks.call(conn_with_subject(), %{"build_run_id" => "nonexistent"})

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text == "Gradle build not found: nonexistent"
    end
  end
end
