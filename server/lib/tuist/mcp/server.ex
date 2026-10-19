defmodule Tuist.MCP.Server do
  @moduledoc false

  alias Tuist.Environment
  alias Tuist.MCP.Components.Prompts
  alias Tuist.MCP.Components.Tools

  # Backed by the hosted Typesense search service, so only offered on the
  # Tuist-hosted installation.
  @hosted_tools [
    Tools.SearchTuist
  ]

  @codebase_tools [
    Tools.SearchTuistCode,
    Tools.ListTuistFiles,
    Tools.ReadTuistFile
  ]

  @tools [
    Tools.GetGradleIntegrationGuide,
    Tools.GetBazelIntegrationGuide,
    Tools.ListAccounts,
    Tools.GetOrganization,
    Tools.ListAccountTokens,
    Tools.GetAccountToken,
    Tools.CreateOrganization,
    Tools.CreateProject,
    Tools.AddOrganizationMember,
    Tools.InviteOrganizationMember,
    Tools.CancelOrganizationInvitation,
    Tools.ListRunnerJobs,
    Tools.GetRunnerJob,
    Tools.ListRunnerJobSteps,
    Tools.ListRunnerJobMetrics,
    Tools.ListRunnerJobLogs,
    Tools.ListRunnerWorkflows,
    Tools.ListRunnerProfiles,
    Tools.GetRunnerCatalog,
    Tools.CreateRunnerProfile,
    Tools.UpdateRunnerProfile,
    Tools.DeleteRunnerProfile,
    Tools.ListRunnerVolumes,
    Tools.GetRunnerVolume,
    Tools.ListRunnerVolumeJobs,
    Tools.ListRunnerJobVolumes,
    Tools.GetRunnerVolumeAnalytics,
    Tools.ClearRunnerVolume,
    Tools.ListWebhookEndpoints,
    Tools.GetWebhookEndpoint,
    Tools.ListWebhookDeliveryAttempts,
    Tools.GetWebhookDeliveryAttempt,
    Tools.ListXcodeBuilds,
    Tools.GetXcodeBuild,
    Tools.ListXcodeBuildTargets,
    Tools.ListXcodeBuildFiles,
    Tools.ListXcodeBuildSteps,
    Tools.GetXcodeBuildStep,
    Tools.ListXcodeBuildIssues,
    Tools.ListXcodeBuildCacheTasks,
    Tools.ListXcodeBuildCASOutputs,
    Tools.ListGradleBuilds,
    Tools.GetGradleBuild,
    Tools.ListGradleBuildTasks,
    Tools.ListGradleBuildSteps,
    Tools.GetGradleBuildStep,
    Tools.ListBazelBuildSteps,
    Tools.GetBazelBuildStep,
    Tools.ListBazelInvocations,
    Tools.GetBazelInvocation,
    Tools.ListBazelInvocationLogs,
    Tools.GetBazelInvocationLog,
    Tools.ListBazelCacheEvents,
    Tools.GetBazelCacheEvent,
    Tools.ListBuildEntities,
    Tools.GetBuildEntity,
    Tools.ListBuildEntityHistory,
    Tools.ListTestRuns,
    Tools.ListTestModuleRuns,
    Tools.ListTestSuiteRuns,
    Tools.ListTestCaseRuns,
    Tools.ListTestCases,
    Tools.ListTestCaseEvents,
    Tools.GetTestCase,
    Tools.UpdateTestCase,
    Tools.GetTestRun,
    Tools.GetTestCaseRun,
    Tools.ListTestCaseRunAttachments,
    Tools.ListBundles,
    Tools.GetBundle,
    Tools.GetBundleArtifactTree,
    Tools.ListGenerations,
    Tools.GetGeneration,
    Tools.ListCacheRuns,
    Tools.GetCacheRun,
    Tools.ListAutomationAlerts,
    Tools.GetAutomationAlert,
    Tools.ListAutomationAlertRevisions,
    Tools.ListProjectNotificationAlerts,
    Tools.ListXcodeModuleCacheTargets,
    Tools.ListXcodeTestTargets,
    Tools.ListProjects,
    Tools.GetProject,
    Tools.ListProjectTokens,
    Tools.StartProjectLogoUpload,
    Tools.CompleteProjectLogoUpload,
    Tools.ListPreviews,
    Tools.GetPreview,
    Tools.GetLatestPreview
  ]

  @prompts [
    Prompts.FixFlakyTest,
    Prompts.CompareBuilds,
    Prompts.CompareTestRuns,
    Prompts.CompareBundles,
    Prompts.CompareTestCase,
    Prompts.CompareGenerations,
    Prompts.CompareCacheRuns,
    Prompts.AnalyzeSelectiveTesting,
    Prompts.IntegrateGradleProject,
    Prompts.IntegrateBazelProject,
    Prompts.IntegrateXcodeProject
  ]

  @codebase_prompts [
    Prompts.AskTuist
  ]

  @source_capabilities """
  `search_tuist` searches public Tuist documentation, API reference, releases, and community content. `search_tuist_code`, `list_tuist_files`, and `read_tuist_file` return public Tuist source from a fixed revision, including the source revision and revision-pinned links. These source tools have bounded results; `truncated` and `truncation_reason` indicate partial results, and truncated file reads include `next_start_line` for continuation.
  """

  @authentication_information """
  This server uses OAuth 2.0 with dynamic client registration; the client completes the standard browser authorization flow. Model Context Protocol authentication only authorizes Tuist tools; it does not authenticate local command-line tools or build-system integrations.
  """

  def server do
    EMCP.Server.new(
      name: "tuist",
      version: "1.38.0",
      title: "Tuist",
      description: "Tuist project setup, build, cache, and test insights.",
      instructions: instructions(),
      tools: tools(),
      prompts: prompts()
    )
  end

  defp tools do
    hosted_tools = if Environment.tuist_hosted?(), do: @hosted_tools, else: []
    codebase_tools = if codebase_search_enabled?(), do: @codebase_tools, else: []
    hosted_tools ++ codebase_tools ++ @tools
  end

  defp prompts, do: if(codebase_search_enabled?(), do: @codebase_prompts ++ @prompts, else: @prompts)

  defp instructions do
    if codebase_search_enabled?() do
      @source_capabilities <> "\n" <> @authentication_information
    else
      @authentication_information
    end
  end

  defp codebase_search_enabled? do
    Environment.tuist_hosted?() and Environment.codebase_search_enabled?()
  end
end
