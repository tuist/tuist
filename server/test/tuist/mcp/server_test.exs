defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Environment
  alias Tuist.MCP.Components.Tools.AddOrganizationMember
  alias Tuist.MCP.Components.Tools.CreateOrganization
  alias Tuist.MCP.Components.Tools.CreateProject
  alias Tuist.MCP.Components.Tools.GetBazelIntegrationGuide
  alias Tuist.MCP.Components.Tools.GetGradleIntegrationGuide
  alias Tuist.MCP.Components.Tools.UpdateTestCase
  alias Tuist.MCP.Server
  alias Tuist.MCP.Tool

  describe "server/0" do
    test "returns a server with all tools" do
      server = Server.server()

      tool_names = server.tools |> Map.keys() |> Enum.sort()

      assert "get_gradle_integration_guide" in tool_names
      assert "get_bazel_integration_guide" in tool_names
      assert "list_accounts" in tool_names
      assert "get_organization" in tool_names
      assert "list_account_tokens" in tool_names
      assert "get_account_token" in tool_names
      assert "create_organization" in tool_names
      assert "create_project" in tool_names
      assert "add_organization_member" in tool_names
      assert "list_runner_jobs" in tool_names
      assert "get_runner_job" in tool_names
      assert "list_runner_job_steps" in tool_names
      assert "list_runner_job_metrics" in tool_names
      assert "list_runner_job_logs" in tool_names
      assert "list_runner_workflows" in tool_names
      assert "list_runner_profiles" in tool_names
      assert "list_webhook_endpoints" in tool_names
      assert "get_webhook_endpoint" in tool_names
      assert "list_webhook_delivery_attempts" in tool_names
      assert "get_webhook_delivery_attempt" in tool_names
      assert "list_xcode_builds" in tool_names
      assert "get_xcode_build" in tool_names
      assert "list_xcode_build_targets" in tool_names
      assert "list_xcode_build_files" in tool_names
      assert "list_xcode_build_issues" in tool_names
      assert "list_xcode_build_cache_tasks" in tool_names
      assert "list_xcode_build_cas_outputs" in tool_names
      assert "list_bazel_invocations" in tool_names
      assert "get_bazel_invocation" in tool_names
      assert "list_bazel_invocation_logs" in tool_names
      assert "get_bazel_invocation_log" in tool_names
      assert "list_bazel_cache_events" in tool_names
      assert "get_bazel_cache_event" in tool_names
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
      assert "list_automation_alerts" in tool_names
      assert "get_automation_alert" in tool_names
      assert "list_automation_alert_revisions" in tool_names
      assert "list_project_notification_alerts" in tool_names
      assert "list_xcode_module_cache_targets" in tool_names
      assert "list_test_case_run_attachments" in tool_names
      assert "list_projects" in tool_names
      assert "get_project" in tool_names
      assert "list_project_tokens" in tool_names
      assert "list_previews" in tool_names
      assert "get_preview" in tool_names
      assert "get_latest_preview" in tool_names
      assert server.version == "1.26.0"
      assert server.instructions =~ "agent_auth.skill"
      assert server.instructions =~ "identity-assertion exchange"
      assert server.instructions =~ "enter the code on the Tuist page"
      assert server.instructions =~ "explicitly ask the user to confirm the email address"

      assert server.instructions =~
               "The `get_gradle_integration_guide` and `get_bazel_integration_guide` tools provide the Gradle, Android, and Bazel integration workflows"

      assert server.instructions =~ "Gradle and Bazel require separate `tuist auth whoami --url` authentication"
    end

    test "offers search_tuist only on the Tuist-hosted installation" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      assert "search_tuist" in Map.keys(Server.server().tools)

      stub(Environment, :tuist_hosted?, fn -> false end)
      refute "search_tuist" in Map.keys(Server.server().tools)
    end

    test "offers codebase tools only when the hosted codebase service is configured" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :codebase_search_enabled?, fn -> true end)

      tool_names = Map.keys(Server.server().tools)
      assert "search_tuist_code" in tool_names
      assert "list_tuist_files" in tool_names
      assert "read_tuist_file" in tool_names

      stub(Environment, :codebase_search_enabled?, fn -> false end)
      tool_names = Map.keys(Server.server().tools)
      refute "search_tuist_code" in tool_names
      refute "list_tuist_files" in tool_names
      refute "read_tuist_file" in tool_names

      stub(Environment, :tuist_hosted?, fn -> false end)
      stub(Environment, :codebase_search_enabled?, fn -> true end)
      refute "search_tuist_code" in Map.keys(Server.server().tools)
    end

    test "every tool exposes descriptions, schemas, a human-readable title, and explicit review hints" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :codebase_search_enabled?, fn -> true end)
      server = Server.server()

      for {name, module} <- server.tools do
        descriptor = Tool.descriptor(module)
        annotations = descriptor["annotations"]

        assert is_binary(descriptor["description"]) and descriptor["description"] != "",
               "tool #{name} is missing a non-empty description"

        assert descriptor["inputSchema"] == module.input_schema()
        assert descriptor["outputSchema"] == module.output_schema()
        assert descriptor["outputSchema"]["type"] == "object"
        assert is_map(descriptor["outputSchema"]["properties"])

        assert descriptor["outputSchema"]["additionalProperties"] == false,
               "tool #{name} must reject undeclared output properties"

        ExJsonSchema.Schema.resolve(descriptor["outputSchema"])

        assert is_binary(annotations[:title]) and annotations[:title] != "",
               "tool #{name} is missing a non-empty title annotation"

        assert is_boolean(annotations[:readOnlyHint]),
               "tool #{name} must declare readOnlyHint"

        assert is_boolean(annotations[:openWorldHint]),
               "tool #{name} must declare openWorldHint"

        assert is_boolean(annotations[:destructiveHint]),
               "tool #{name} must declare destructiveHint"
      end

      assert CreateOrganization.annotations()[:readOnlyHint] == false
      assert CreateProject.annotations()[:readOnlyHint] == false
      assert GetGradleIntegrationGuide.annotations()[:readOnlyHint] == true
      assert GetBazelIntegrationGuide.annotations()[:readOnlyHint] == true
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
      assert "integrate_bazel_project" in prompt_names
      assert "integrate_xcode_project" in prompt_names
    end

    test "offers the question-answering prompt with the codebase tools" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :codebase_search_enabled?, fn -> true end)
      assert "ask_tuist" in Map.keys(Server.server().prompts)

      stub(Environment, :codebase_search_enabled?, fn -> false end)
      refute "ask_tuist" in Map.keys(Server.server().prompts)
    end

    test "instructs clients to answer questions with source-backed tools when they are available" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :codebase_search_enabled?, fn -> true end)

      instructions = Server.server().instructions

      assert instructions =~ "Use the relevant Tuist tool"
      assert instructions =~ "search_tuist_code"
      assert instructions =~ "treat truncated results as partial"
      assert instructions =~ "source revision"

      stub(Environment, :codebase_search_enabled?, fn -> false end)
      instructions = Server.server().instructions
      refute instructions =~ "Use the relevant Tuist tool"
      assert instructions =~ "agent_auth.skill"
    end

    test "tool descriptions state their capability without steering tool selection" do
      stub(Environment, :tuist_hosted?, fn -> true end)
      stub(Environment, :codebase_search_enabled?, fn -> true end)

      for {_name, module} <- Server.server().tools do
        description = Tool.descriptor(module)["description"]

        refute description =~ "Call this first"
        refute description =~ "instead of"
        refute description =~ "general web search"
        refute description =~ "Use this after"
      end
    end

    test "mutating tools advertise annotations that match their effects" do
      assert CreateOrganization.annotations() == %{
               title: "Create Organization",
               readOnlyHint: false,
               openWorldHint: false,
               destructiveHint: false
             }

      assert CreateProject.annotations() == %{
               title: "Create Project",
               readOnlyHint: false,
               openWorldHint: false,
               destructiveHint: false
             }

      assert AddOrganizationMember.annotations() == %{
               title: "Add Organization Member",
               readOnlyHint: false,
               openWorldHint: false,
               destructiveHint: true
             }

      assert UpdateTestCase.annotations() == %{
               title: "Update Test Case",
               readOnlyHint: false,
               openWorldHint: true,
               destructiveHint: true
             }

      assert Tool.descriptor(UpdateTestCase)["description"] =~ "webhook endpoints"
    end
  end
end
