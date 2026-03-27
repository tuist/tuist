defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Server
  alias Tuist.Projects

  describe "server/0" do
    test "returns a server with all tools" do
      server = Server.server()

      tool_names = server.tools |> Map.keys() |> Enum.sort()

      assert "list_xcode_builds" in tool_names
      assert "get_xcode_build" in tool_names
      assert "list_xcode_build_targets" in tool_names
      assert "list_xcode_build_files" in tool_names
      assert "list_xcode_build_issues" in tool_names
      assert "list_xcode_build_cache_tasks" in tool_names
      assert "list_xcode_build_cas_outputs" in tool_names
      assert "list_test_runs" in tool_names
      assert "list_test_module_runs" in tool_names
      assert "list_test_suite_runs" in tool_names
      assert "list_test_case_runs" in tool_names
      assert "list_test_cases" in tool_names
      assert "get_test_case" in tool_names
      assert "get_test_run" in tool_names
      assert "get_test_case_run" in tool_names
      assert "list_bundles" in tool_names
      assert "get_bundle" in tool_names
      assert "get_bundle_artifact_tree" in tool_names
      assert "list_generations" in tool_names
      assert "get_generation" in tool_names
      assert "list_cache_runs" in tool_names
      assert "get_cache_run" in tool_names
      assert "list_xcode_module_cache_targets" in tool_names
      assert "list_test_case_run_attachments" in tool_names
      assert "list_projects" in tool_names
    end

    test "returns a server with all prompts" do
      server = Server.server()

      prompt_names = server.prompts |> Map.keys() |> Enum.sort()

      assert "fix_flaky_test" in prompt_names
      assert "compare_builds" in prompt_names
      assert "compare_test_runs" in prompt_names
      assert "compare_bundles" in prompt_names
      assert "compare_test_case" in prompt_names
      assert "compare_generations" in prompt_names
      assert "compare_cache_runs" in prompt_names
    end

    test "list_projects tool returns results" do
      stub(Projects, :list_accessible_projects, fn _subject, _opts -> [] end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      result = Tuist.MCP.Components.Tools.ListProjects.call(conn, %{})

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert JSON.decode!(text) == []
    end
  end
end
