defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Anubis.Server.Frame
  alias Tuist.MCP.Server
  alias Tuist.Projects

  describe "handle_request/2" do
    test "returns tools list" do
      request = %{"method" => "tools/list", "params" => %{}}

      assert {:reply, %{"tools" => tools}, _frame} = Server.handle_request(request, Frame.new())

      tool_names = tools |> Enum.map(& &1.name) |> Enum.sort()

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

    test "returns prompts list" do
      request = %{"method" => "prompts/list", "params" => %{}}

      assert {:reply, %{"prompts" => prompts}, _frame} = Server.handle_request(request, Frame.new())

      prompt_names = prompts |> Enum.map(& &1.name) |> Enum.sort()

      assert "fix_flaky_test" in prompt_names
      assert "compare_builds" in prompt_names
      assert "compare_test_runs" in prompt_names
      assert "compare_bundles" in prompt_names
      assert "compare_test_case" in prompt_names
      assert "compare_generations" in prompt_names
      assert "compare_cache_runs" in prompt_names
    end

    test "calls list_projects tool" do
      stub(Projects, :list_accessible_projects, fn _subject, _opts -> [] end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "list_projects", "arguments" => %{}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      assert JSON.decode!(text) == []
    end

    test "returns error for unknown tool" do
      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert error.message == "Invalid params"
      assert message(error) == "Tool not found: nonexistent"
    end

    test "returns error for unknown method" do
      request = %{"method" => "foo/bar", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_601
      assert error.message == "Method not found"
    end

    test "returns error for tools/call without required params" do
      request = %{"method" => "tools/call", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert message(error) == "Missing required parameter: name."
    end

    test "returns error for prompts/get without name" do
      request = %{"method" => "prompts/get", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert message(error) == "Missing required parameter: name."
    end

    test "returns error for unknown prompt" do
      request = %{
        "method" => "prompts/get",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert error.message == "Invalid params"
      assert message(error) == "Prompt not found: nonexistent"
    end
  end

  defp message(error), do: Map.get(error.data, :message) || Map.get(error.data, "message")
end
