defmodule Tuist.MCP.WebMCP do
  @moduledoc """
  The tool sets the website registers with WebMCP for agents built into the
  browser. Those agents receive the tools without the user adding them and read
  content that builds and tests produce, so no tool that changes data is
  offered: a signed-in account page gets read-only tools, limited to that
  account (`Tuist.MCP.Authorization.account_scope/1`), and other pages only
  the documentation and source tools, which do not depend on who is asking.

  An account page registers only the tools for what it shows, as WebMCP
  recommends, rather than every read-only tool: `dashboard_page/3` names the
  page from its path, and `account_server/2` serves that page's tools for the
  project's build system, together with the tools every page offers.
  """

  alias Tuist.MCP.Components.Tools
  alias Tuist.MCP.Server

  @public_tools [Tools.SearchTuist, Tools.SearchTuistCode, Tools.ListTuistFiles, Tools.ReadTuistFile]

  @every_page_tools @public_tools ++ [Tools.ListProjects, Tools.GetProject]

  @build_tools %{
    xcode: [
      Tools.ListXcodeBuilds,
      Tools.GetXcodeBuild,
      Tools.ListXcodeBuildTargets,
      Tools.ListXcodeBuildFiles,
      Tools.ListXcodeBuildSteps,
      Tools.GetXcodeBuildStep,
      Tools.ListXcodeBuildIssues,
      Tools.ListXcodeBuildCacheTasks,
      Tools.ListXcodeBuildCASOutputs,
      Tools.GetBuildTrace
    ],
    gradle: [
      Tools.ListGradleBuilds,
      Tools.GetGradleBuild,
      Tools.ListGradleBuildTasks,
      Tools.ListGradleBuildSteps,
      Tools.GetGradleBuildStep,
      Tools.GetBuildTrace
    ],
    bazel: [
      Tools.ListBazelInvocations,
      Tools.GetBazelInvocation,
      Tools.ListBazelBuildSteps,
      Tools.GetBazelBuildStep,
      Tools.ListBazelInvocationLogs,
      Tools.GetBazelInvocationLog,
      Tools.ListBazelCacheEvents,
      Tools.GetBazelCacheEvent,
      Tools.GetBuildTrace
    ],
    cargo: [Tools.ListCargoBuilds, Tools.GetCargoBuild],
    mix: [Tools.ListMixBuilds, Tools.GetMixBuild, Tools.GetBuildTrace],
    once: [Tools.ListOnceRuns, Tools.GetOnceRun]
  }

  @build_entity_tools [Tools.ListBuildEntities, Tools.GetBuildEntity, Tools.ListBuildEntityHistory]

  @test_tools [
    Tools.ListTestRuns,
    Tools.GetTestRun,
    Tools.ListTestModuleRuns,
    Tools.ListTestSuiteRuns,
    Tools.ListTestCaseRuns,
    Tools.GetTestCaseRun,
    Tools.ListTestCaseRunAttachments,
    Tools.ListTestCases,
    Tools.GetTestCase,
    Tools.ListTestCaseEvents,
    Tools.GetCoverage,
    Tools.ListCoverageFiles,
    Tools.GetCoverageFile
  ]

  # Selective testing is Xcode's, and Once records its test runs as Once runs.
  @build_system_test_tools %{xcode: [Tools.ListXcodeTestTargets], once: [Tools.ListOnceRuns, Tools.GetOnceRun]}

  @module_cache_tools [
    Tools.ListCacheRuns,
    Tools.GetCacheRun,
    Tools.ListGenerations,
    Tools.GetGeneration,
    Tools.ListXcodeModuleCacheTargets
  ]

  @runner_tools [
    Tools.ListRunnerJobs,
    Tools.GetRunnerJob,
    Tools.ListRunnerJobSteps,
    Tools.ListRunnerJobMetrics,
    Tools.ListRunnerJobLogs,
    Tools.ListRunnerWorkflows,
    Tools.ListRunnerProfiles,
    Tools.GetRunnerCatalog,
    Tools.ListRunnerVolumes,
    Tools.GetRunnerVolume,
    Tools.ListRunnerVolumeJobs,
    Tools.ListRunnerJobVolumes,
    Tools.GetRunnerVolumeAnalytics
  ]

  @webhook_tools [
    Tools.ListWebhookEndpoints,
    Tools.GetWebhookEndpoint,
    Tools.ListWebhookDeliveryAttempts,
    Tools.GetWebhookDeliveryAttempt
  ]

  @project_settings_tools [
    Tools.ListAutomationAlerts,
    Tools.GetAutomationAlert,
    Tools.ListAutomationAlertRevisions,
    Tools.ListProjectNotificationAlerts,
    Tools.ListProjectTokens
  ]

  @build_systems Map.keys(@build_tools)

  @doc """
  The page a dashboard path shows, or nil for a page with no tools of its
  own. `account` is the page's account, and `project` its project, nil on the
  account's own pages.
  """
  def dashboard_page(path, account, project) do
    segments = String.split(path || "", "/", trim: true)
    page = if project, do: project_page(Enum.drop(segments, 2)), else: account_page(Enum.drop(segments, 1))

    # A personal account's settings have no organization to read.
    if page == "organization" and is_nil(account.organization_id), do: nil, else: page
  end

  defp project_page([]), do: "overview"
  defp project_page(["analytics"]), do: "overview"
  defp project_page(["tests" | _]), do: "tests"
  defp project_page(["once", tests | _]) when tests in ["tests", "test-runs"], do: "tests"
  defp project_page([builds | _]) when builds in ["builds", "invocations", "once"], do: "builds"

  defp project_page([cache]) when cache in ~w(xcode-cache gradle-cache bazel-cache mix-cache cargo-cache once-cache),
    do: "builds"

  defp project_page([module_cache | _]) when module_cache in ["module-cache", "runs"], do: "module-cache"
  defp project_page(["bundles" | _]), do: "bundles"
  defp project_page(["previews" | _]), do: "previews"
  defp project_page(["settings" | _]), do: "project-settings"
  defp project_page(["connect"]), do: "connect"
  defp project_page(_segments), do: nil

  defp account_page([]), do: "projects"
  defp account_page(["projects"]), do: "projects"
  defp account_page(["runners" | _]), do: "runners"
  defp account_page(["webhooks" | _]), do: "webhooks"
  defp account_page(["settings", "tokens" | _]), do: "account-tokens"

  defp account_page([organization | _]) when organization in ["settings", "members", "billing", "usage"],
    do: "organization"

  defp account_page(_segments), do: nil

  @doc """
  The read-only tools of a dashboard `page` (see `dashboard_page/3`) and the
  tools every page offers. `build_system` is the page's project's, when it has
  one, and picks the build tools of build, test and overview pages.
  """
  def account_server(page, build_system) do
    page_tools = page_tools(page, Enum.find(@build_systems, &(Atom.to_string(&1) == build_system)))
    restrict(&(&1.annotations().readOnlyHint and &1 in (@every_page_tools ++ page_tools)))
  end

  def public_server, do: restrict(&(&1 in @public_tools))

  defp page_tools("overview", build_system),
    do:
      Map.get(@build_tools, build_system, []) ++
        [Tools.ListTestRuns, Tools.GetTestRun] ++ overview_bundle_tools(build_system)

  defp page_tools("builds", build_system), do: Map.get(@build_tools, build_system, []) ++ @build_entity_tools

  defp page_tools("tests", build_system), do: @test_tools ++ Map.get(@build_system_test_tools, build_system, [])

  defp page_tools("module-cache", _build_system), do: @module_cache_tools
  defp page_tools("bundles", _build_system), do: [Tools.ListBundles, Tools.GetBundle, Tools.GetBundleArtifactTree]
  defp page_tools("previews", _build_system), do: [Tools.ListPreviews, Tools.GetPreview, Tools.GetLatestPreview]
  defp page_tools("project-settings", _build_system), do: @project_settings_tools

  defp page_tools("connect", :gradle), do: [Tools.GetGradleIntegrationGuide]
  defp page_tools("connect", :bazel), do: [Tools.GetBazelIntegrationGuide]

  defp page_tools("projects", _build_system), do: [Tools.ListAccounts]
  defp page_tools("runners", _build_system), do: @runner_tools
  defp page_tools("webhooks", _build_system), do: @webhook_tools
  defp page_tools("account-tokens", _build_system), do: [Tools.ListAccountTokens, Tools.GetAccountToken]
  defp page_tools("organization", _build_system), do: [Tools.GetOrganization]
  defp page_tools(_page, _build_system), do: []

  # Only the Xcode overview shows bundles.
  defp overview_bundle_tools(:xcode), do: [Tools.ListBundles]
  defp overview_bundle_tools(_build_system), do: []

  # Keeps the tools the hosted and feature-flag gates in `Server` already
  # selected. Prompts are not exposed through WebMCP.
  defp restrict(keep?) do
    server = Server.server()
    %{server | tools: Map.filter(server.tools, fn {_name, module} -> keep?.(module) end), prompts: %{}}
  end
end
