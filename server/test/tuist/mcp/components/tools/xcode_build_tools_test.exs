defmodule Tuist.MCP.Components.Tools.XcodeBuildToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Builds
  alias Tuist.MCP.Components.Tools.GetXcodeBuild
  alias Tuist.MCP.Components.Tools.ListXcodeBuildCacheTasks
  alias Tuist.MCP.Components.Tools.ListXcodeBuildCASOutputs
  alias Tuist.MCP.Components.Tools.ListXcodeBuildFiles
  alias Tuist.MCP.Components.Tools.ListXcodeBuildIssues
  alias Tuist.MCP.Components.Tools.ListXcodeBuilds
  alias Tuist.MCP.Components.Tools.ListXcodeBuildTargets
  alias Tuist.Projects

  defp conn_with_subject do
    %Plug.Conn{assigns: %{current_subject: :subject}}
  end

  describe "list_xcode_builds" do
    test "returns paginated builds" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_runs, fn _attrs ->
        {[
           %{
             id: "build-1",
             duration: 5000,
             status: "success",
             category: "clean",
             scheme: "App",
             configuration: "Debug",
             is_ci: false,
             git_branch: "main",
             git_commit_sha: "abc123",
             cacheable_tasks_count: 10,
             cacheable_task_local_hits_count: 5,
             cacheable_task_remote_hits_count: 3,
             inserted_at: ~N[2024-01-01 12:00:00]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      result =
        ListXcodeBuilds.call(conn_with_subject(), %{
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["builds"]) == 1
      assert hd(result["builds"])["id"] == "build-1"
      assert hd(result["builds"])["duration"] == 5000
    end

    test "requires :build_read authorization" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      result =
        ListXcodeBuilds.call(conn_with_subject(), %{
          "account_handle" => "acme",
          "project_handle" => "app"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} = result
      assert text == "You do not have access to project: acme/app"
    end
  end

  describe "get_xcode_build" do
    test "returns build details" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" ->
        {:ok,
         %{
           id: "build-1",
           duration: 5000,
           status: "success",
           category: "clean",
           scheme: "App",
           configuration: "Debug",
           xcode_version: "15.0",
           macos_version: "14.0",
           model_identifier: "MacBookPro18,1",
           is_ci: false,
           git_branch: "main",
           git_commit_sha: "abc123",
           git_ref: "refs/heads/main",
           cacheable_tasks_count: 10,
           cacheable_task_local_hits_count: 5,
           cacheable_task_remote_hits_count: 3,
           project_id: 1,
           inserted_at: ~N[2024-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      result = GetXcodeBuild.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert result["id"] == "build-1"
      assert result["duration"] == 5000
      assert result["xcode_version"] == "15.0"
    end
  end

  describe "list_xcode_build_targets" do
    test "returns build targets" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" ->
        {:ok, %{id: "build-1", project_id: 1}}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_targets, fn _attrs ->
        {[
           %{
             name: "AppTarget",
             project: "App",
             build_duration: 3000,
             compilation_duration: 2500,
             status: "success"
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      result = ListXcodeBuildTargets.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["targets"]) == 1
      assert hd(result["targets"])["name"] == "AppTarget"
      assert hd(result["targets"])["build_duration"] == 3000
    end
  end

  describe "list_xcode_build_files" do
    test "returns build files" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> {:ok, %{id: "build-1", project_id: 1}} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_files, fn _attrs ->
        {[
           %{
             type: "swift",
             target: "AppTarget",
             project: "App",
             path: "Sources/App.swift",
             compilation_duration: 150
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      result = ListXcodeBuildFiles.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["files"]) == 1
      assert hd(result["files"])["path"] == "Sources/App.swift"
    end
  end

  describe "list_xcode_build_issues" do
    test "returns build issues" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> {:ok, %{id: "build-1", project_id: 1}} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_issues, fn "build-1" ->
        [
          %{
            type: "error",
            target: "AppTarget",
            project: "App",
            title: "Type mismatch",
            message: "Cannot convert Int to String",
            signature: "sig123",
            step_type: "swift_compilation",
            path: "Sources/App.swift",
            starting_line: 42,
            ending_line: 42,
            starting_column: 10,
            ending_column: 20
          }
        ]
      end)

      result = ListXcodeBuildIssues.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result) == 1
      assert hd(result)["title"] == "Type mismatch"
    end
  end

  describe "list_xcode_build_cache_tasks" do
    test "returns cache tasks" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> {:ok, %{id: "build-1", project_id: 1}} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_cacheable_tasks, fn _attrs ->
        {[
           %{
             type: "swift",
             status: "hit_remote",
             key: "abc123",
             read_duration: 50.0,
             write_duration: nil,
             description: "AppTarget",
             cas_output_node_ids: ["node-1"]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      result = ListXcodeBuildCacheTasks.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["tasks"]) == 1
      assert hd(result["tasks"])["status"] == "hit_remote"
    end
  end

  describe "list_xcode_build_cas_outputs" do
    test "returns CAS outputs" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> {:ok, %{id: "build-1", project_id: 1}} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_cas_outputs, fn _attrs ->
        {[
           %{
             node_id: "node-1",
             checksum: "sha256abc",
             size: 1024,
             compressed_size: 512,
             duration: 100,
             operation: "download",
             type: "swift"
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      result = ListXcodeBuildCASOutputs.call(conn_with_subject(), %{"build_run_id" => "build-1"})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      result = JSON.decode!(text)
      assert length(result["outputs"]) == 1
      assert hd(result["outputs"])["node_id"] == "node-1"
      assert hd(result["outputs"])["size"] == 1024
    end
  end
end
