defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.Components.Tools.AddOrganizationMember
  alias Tuist.MCP.Components.Tools.CreateOrganization
  alias Tuist.MCP.Components.Tools.CreateProject
  alias Tuist.MCP.Server

  describe "server/0" do
    test "returns a server with all tools" do
      server = Server.server()

      tool_names = server.tools |> Map.keys() |> Enum.sort()

      assert "create_organization" in tool_names
      assert "create_project" in tool_names
      assert "add_organization_member" in tool_names
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

    test "every tool exposes a human-readable title and explicit review hints" do
      server = Server.server()

      for {name, module} <- server.tools do
        annotations = module.annotations()

        assert is_binary(annotations[:title]) and annotations[:title] != "",
               "tool #{name} is missing a non-empty :title annotation"

        assert is_boolean(annotations[:readOnlyHint]),
               "tool #{name} must declare readOnlyHint"

        assert annotations[:openWorldHint] == false,
               "tool #{name} must declare openWorldHint: false"

        assert is_boolean(annotations[:destructiveHint]),
               "tool #{name} must declare destructiveHint"
      end

      assert CreateOrganization.annotations()[:readOnlyHint] == false
      assert CreateProject.annotations()[:readOnlyHint] == false
      assert AddOrganizationMember.annotations()[:readOnlyHint] == false
      assert AddOrganizationMember.annotations()[:destructiveHint] == true
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
      assert "integrate_gradle_project" in prompt_names
      assert "integrate_xcode_project" in prompt_names
    end
  end
end
