defmodule Tuist.MCP.Components.Tools.GenerationAndCacheToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.CommandEvents
  alias Tuist.MCP.Components.Tools.GetCacheRun
  alias Tuist.MCP.Components.Tools.GetGeneration
  alias Tuist.MCP.Components.Tools.ListCacheRuns
  alias Tuist.MCP.Components.Tools.ListGenerations
  alias Tuist.MCP.Components.Tools.ListXcodeModuleCacheTargets
  alias Tuist.Projects
  alias Tuist.Xcode

  describe "list_generations" do
    test "returns paginated generations" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(CommandEvents, :list_command_events, fn _attrs ->
        {[
           %{
             id: "gen-1",
             name: "generate",
             duration: 5000,
             status: 0,
             tuist_version: "4.0.0",
             swift_version: "5.10",
             macos_version: "14.0",
             is_ci: false,
             git_branch: "main",
             git_commit_sha: "abc123",
             git_ref: nil,
             command_arguments: nil,
             cacheable_targets: ["App", "Core"],
             local_cache_target_hits: ["Core"],
             remote_cache_target_hits: [],
             created_at: ~N[2025-01-01 12:00:00],
             user_account_name: nil
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

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"text" => json}]} =
               ListGenerations.call(conn, %{
                 "account_handle" => "acme",
                 "project_handle" => "app"
               })

      data = Jason.decode!(json)
      assert length(data["generations"]) == 1
      assert hd(data["generations"])["id"] == "gen-1"
      assert hd(data["generations"])["status"] == "success"
      assert hd(data["generations"])["cacheable_targets"] == ["App", "Core"]
    end
  end

  describe "get_generation" do
    test "returns generation details" do
      stub(CommandEvents, :get_command_event_by_id, fn "gen-1" ->
        {:ok,
         %{
           id: "gen-1",
           name: "generate",
           project_id: 1,
           duration: 5000,
           status: 0,
           tuist_version: "4.0.0",
           swift_version: "5.10",
           macos_version: "14.0",
           is_ci: false,
           git_branch: "main",
           git_commit_sha: "abc123",
           git_ref: nil,
           command_arguments: nil,
           cacheable_targets: ["App"],
           local_cache_target_hits: [],
           remote_cache_target_hits: [],
           created_at: ~N[2025-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"text" => json}]} =
               GetGeneration.call(conn, %{"generation_id" => "gen-1"})

      data = Jason.decode!(json)
      assert data["id"] == "gen-1"
      assert data["status"] == "success"
    end

    test "rejects non-generate events" do
      stub(CommandEvents, :get_command_event_by_id, fn "cache-1" ->
        {:ok, %{id: "cache-1", name: "cache", project_id: 1}}
      end)

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               GetGeneration.call(conn, %{"generation_id" => "cache-1"})

      assert text =~ "Generation not found"
    end
  end

  describe "list_cache_runs" do
    test "returns paginated cache runs" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(CommandEvents, :list_command_events, fn _attrs ->
        {[
           %{
             id: "cr-1",
             name: "cache",
             duration: 3000,
             status: 0,
             tuist_version: "4.0.0",
             swift_version: "5.10",
             macos_version: "14.0",
             is_ci: true,
             git_branch: "main",
             git_commit_sha: "def456",
             git_ref: nil,
             command_arguments: "warm",
             cacheable_targets: ["App", "Core", "UI"],
             local_cache_target_hits: ["Core"],
             remote_cache_target_hits: ["UI"],
             created_at: ~N[2025-01-01 12:00:00],
             user_account_name: nil
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

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"text" => json}]} =
               ListCacheRuns.call(conn, %{
                 "account_handle" => "acme",
                 "project_handle" => "app"
               })

      data = Jason.decode!(json)
      assert length(data["cache_runs"]) == 1
      assert hd(data["cache_runs"])["id"] == "cr-1"
    end
  end

  describe "get_cache_run" do
    test "returns cache run details" do
      stub(CommandEvents, :get_command_event_by_id, fn "cr-1" ->
        {:ok,
         %{
           id: "cr-1",
           name: "cache",
           project_id: 1,
           duration: 3000,
           status: 0,
           tuist_version: "4.0.0",
           swift_version: "5.10",
           macos_version: "14.0",
           is_ci: true,
           git_branch: "main",
           git_commit_sha: "def456",
           git_ref: nil,
           command_arguments: "warm",
           cacheable_targets: ["App"],
           local_cache_target_hits: [],
           remote_cache_target_hits: [],
           created_at: ~N[2025-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"text" => json}]} =
               GetCacheRun.call(conn, %{"cache_run_id" => "cr-1"})

      data = Jason.decode!(json)
      assert data["id"] == "cr-1"
      assert data["command_arguments"] == "warm"
    end
  end

  describe "list_xcode_module_cache_targets" do
    test "returns module cache targets with subhashes" do
      stub(CommandEvents, :get_command_event_by_id, fn "gen-1" ->
        {:ok,
         %{
           id: "gen-1",
           name: "generate",
           project_id: 1,
           created_at: ~N[2025-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(Xcode, :binary_cache_analytics, fn _event, _flop_params ->
        {%{
           cacheable_targets: [
             %{
               name: "App",
               binary_cache_hit: :miss,
               binary_cache_hash: "hash-abc",
               product: "App.app",
               bundle_id: "com.example.app",
               product_name: "App",
               external_hash: "",
               sources_hash: "src-hash",
               resources_hash: "res-hash",
               copy_files_hash: "",
               core_data_models_hash: "",
               target_scripts_hash: "",
               environment_hash: "",
               headers_hash: "",
               deployment_target_hash: "",
               info_plist_hash: "",
               entitlements_hash: "",
               dependencies_hash: "dep-hash",
               project_settings_hash: "",
               target_settings_hash: "",
               buildable_folders_hash: "",
               destinations: ["iphone"],
               additional_strings: []
             }
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"text" => json}]} =
               ListXcodeModuleCacheTargets.call(conn, %{"run_id" => "gen-1"})

      data = Jason.decode!(json)
      assert length(data["targets"]) == 1
      target = hd(data["targets"])
      assert target["name"] == "App"
      assert target["cache_status"] == "miss"
      assert target["cache_hash"] == "hash-abc"
      assert target["subhashes"]["sources"] == "src-hash"
      assert target["subhashes"]["dependencies"] == "dep-hash"
      refute Map.has_key?(target["subhashes"], "headers")
    end
  end
end
