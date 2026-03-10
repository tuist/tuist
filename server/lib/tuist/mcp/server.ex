defmodule Tuist.MCP.Server do
  @moduledoc false

  use Anubis.Server,
    name: "tuist",
    version: "1.4.1",
    capabilities: [
      {:tools, list_changed?: false},
      {:prompts, list_changed?: false}
    ],
    protocol_versions: ["2025-03-26"]

  alias Anubis.MCP.Error
  alias Anubis.Server.Frame
  alias Anubis.Server.Handlers
  alias Tuist.MCP.Components.Prompts.CompareBuilds
  alias Tuist.MCP.Components.Prompts.CompareBundles
  alias Tuist.MCP.Components.Prompts.CompareCacheRuns
  alias Tuist.MCP.Components.Prompts.CompareGenerations
  alias Tuist.MCP.Components.Prompts.CompareTestCase
  alias Tuist.MCP.Components.Prompts.CompareTestRuns
  alias Tuist.MCP.Components.Prompts.FixFlakyTest
  alias Tuist.MCP.Components.Tools.GetBundle
  alias Tuist.MCP.Components.Tools.GetBundleArtifactTree
  alias Tuist.MCP.Components.Tools.GetCacheRun
  alias Tuist.MCP.Components.Tools.GetGeneration
  alias Tuist.MCP.Components.Tools.GetTestCase
  alias Tuist.MCP.Components.Tools.GetTestCaseRun
  alias Tuist.MCP.Components.Tools.GetTestRun
  alias Tuist.MCP.Components.Tools.GetXcodeBuild
  alias Tuist.MCP.Components.Tools.ListBundles
  alias Tuist.MCP.Components.Tools.ListCacheRuns
  alias Tuist.MCP.Components.Tools.ListGenerations
  alias Tuist.MCP.Components.Tools.ListProjects
  alias Tuist.MCP.Components.Tools.ListTestCaseRunAttachments
  alias Tuist.MCP.Components.Tools.ListTestCaseRuns
  alias Tuist.MCP.Components.Tools.ListTestCases
  alias Tuist.MCP.Components.Tools.ListTestModuleRuns
  alias Tuist.MCP.Components.Tools.ListTestRuns
  alias Tuist.MCP.Components.Tools.ListTestSuiteRuns
  alias Tuist.MCP.Components.Tools.ListXcodeBuildCacheTasks
  alias Tuist.MCP.Components.Tools.ListXcodeBuildCASOutputs
  alias Tuist.MCP.Components.Tools.ListXcodeBuildFiles
  alias Tuist.MCP.Components.Tools.ListXcodeBuildIssues
  alias Tuist.MCP.Components.Tools.ListXcodeBuilds
  alias Tuist.MCP.Components.Tools.ListXcodeBuildTargets
  alias Tuist.MCP.Components.Tools.ListXcodeModuleCacheTargets

  # Xcode build tools
  component(ListXcodeBuilds, name: "list_xcode_builds")
  component(GetXcodeBuild, name: "get_xcode_build")
  component(ListXcodeBuildTargets, name: "list_xcode_build_targets")
  component(ListXcodeBuildFiles, name: "list_xcode_build_files")
  component(ListXcodeBuildIssues, name: "list_xcode_build_issues")
  component(ListXcodeBuildCacheTasks, name: "list_xcode_build_cache_tasks")
  component(ListXcodeBuildCASOutputs, name: "list_xcode_build_cas_outputs")

  # Test tools
  component(ListTestRuns, name: "list_test_runs")
  component(ListTestModuleRuns, name: "list_test_module_runs")
  component(ListTestSuiteRuns, name: "list_test_suite_runs")
  component(ListTestCaseRuns, name: "list_test_case_runs")
  component(ListTestCases, name: "list_test_cases")
  component(GetTestCase, name: "get_test_case")
  component(GetTestRun, name: "get_test_run")
  component(GetTestCaseRun, name: "get_test_case_run")
  component(ListTestCaseRunAttachments, name: "list_test_case_run_attachments")

  # Bundle tools
  component(ListBundles, name: "list_bundles")
  component(GetBundle, name: "get_bundle")
  component(GetBundleArtifactTree, name: "get_bundle_artifact_tree")

  # Generation tools
  component(ListGenerations, name: "list_generations")
  component(GetGeneration, name: "get_generation")

  # Cache run tools
  component(ListCacheRuns, name: "list_cache_runs")
  component(GetCacheRun, name: "get_cache_run")

  # Module cache tools
  component(ListXcodeModuleCacheTargets, name: "list_xcode_module_cache_targets")

  # Project tools
  component(ListProjects, name: "list_projects")

  # Prompts
  component(FixFlakyTest, name: "fix_flaky_test")
  component(CompareBuilds, name: "compare_builds")
  component(CompareTestRuns, name: "compare_test_runs")
  component(CompareBundles, name: "compare_bundles")
  component(CompareTestCase, name: "compare_test_case")
  component(CompareGenerations, name: "compare_generations")
  component(CompareCacheRuns, name: "compare_cache_runs")

  @impl Anubis.Server
  def handle_request(%{"method" => "tools/call", "params" => %{"name" => _name} = params} = request, %Frame{} = frame) do
    request = put_in(request, ["params"], Map.put_new(params, "arguments", %{}))
    safe_handle(request, frame)
  end

  @impl Anubis.Server
  def handle_request(%{"method" => "tools/call"}, %Frame{} = frame) do
    {:error, invalid_params_error("Missing required parameter: name."), frame}
  end

  @impl Anubis.Server
  def handle_request(%{"method" => "prompts/get", "params" => %{"name" => _name} = params} = request, %Frame{} = frame) do
    request = put_in(request, ["params"], Map.put_new(params, "arguments", %{}))
    safe_handle(request, frame)
  end

  @impl Anubis.Server
  def handle_request(%{"method" => "prompts/get"}, %Frame{} = frame) do
    {:error, invalid_params_error("Missing required parameter: name."), frame}
  end

  @impl Anubis.Server
  def handle_request(request, %Frame{} = frame), do: safe_handle(request, frame)

  # Wraps Handlers.handle to prevent unhandled exceptions from crashing
  # the MCP Server GenServer, which would take down all in-flight requests.
  defp safe_handle(request, frame) do
    Handlers.handle(request, __MODULE__, frame)
  rescue
    exception ->
      Sentry.capture_exception(exception, stacktrace: __STACKTRACE__)
      {:error, Error.protocol(:internal_error, %{message: Exception.message(exception)}), frame}
  end

  defp invalid_params_error(message) do
    Error.protocol(:invalid_params, %{message: message})
  end
end
