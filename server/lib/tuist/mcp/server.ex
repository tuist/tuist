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
    Tools.ListAccounts,
    Tools.GetOrganization,
    Tools.ListAccountTokens,
    Tools.GetAccountToken,
    Tools.CreateOrganization,
    Tools.CreateProject,
    Tools.AddOrganizationMember,
    Tools.ListRunnerJobs,
    Tools.GetRunnerJob,
    Tools.ListRunnerJobSteps,
    Tools.ListRunnerJobMetrics,
    Tools.ListRunnerJobLogs,
    Tools.ListRunnerWorkflows,
    Tools.ListRunnerProfiles,
    Tools.ListWebhookEndpoints,
    Tools.GetWebhookEndpoint,
    Tools.ListWebhookDeliveryAttempts,
    Tools.GetWebhookDeliveryAttempt,
    Tools.ListXcodeBuilds,
    Tools.GetXcodeBuild,
    Tools.ListXcodeBuildTargets,
    Tools.ListXcodeBuildFiles,
    Tools.ListXcodeBuildIssues,
    Tools.ListXcodeBuildCacheTasks,
    Tools.ListXcodeBuildCASOutputs,
    Tools.ListGradleBuilds,
    Tools.GetGradleBuild,
    Tools.ListGradleBuildTasks,
    Tools.ListBazelInvocations,
    Tools.GetBazelInvocation,
    Tools.ListBazelCacheEvents,
    Tools.GetBazelCacheEvent,
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
    Prompts.IntegrateXcodeProject
  ]

  @codebase_prompts [
    Prompts.AskTuist
  ]

  @source_answer_instructions """
  Use the relevant Tuist tool when its documentation or source results are needed to answer a Tuist question. `search_tuist` covers public explanations and terminology. When current behavior depends on implementation, `search_tuist_code`, `list_tuist_files`, and `read_tuist_file` provide a fixed source revision; inspect focused tests and call sites, treat truncated results as partial, and cite returned links and the source revision. Keep the answer focused on the user's question rather than describing the codebase.
  """

  @agent_workflow_instructions """
  If this server is unauthenticated, fetch the `auth_md` URL from the 401 response. If only the discovery documents are available, read `agent_auth.skill` from the authorization-server metadata. Follow that deployment-local document through registration, identity-assertion exchange, and claim polling before falling back to browser Open Authorization. Never invent credentials. Prefer anonymous registration when no trusted provider assertion is available. Before sending a service-authenticated email or starting an anonymous claim, explicitly ask the user to confirm the email address for their Tuist account; do not derive it from a provider profile, Git configuration, environment variables, or session metadata. During a claim, show the verification link and six-digit code together, and tell the user to enter the code on the Tuist page rather than sending it back to the agent. The `get_gradle_integration_guide` tool provides the Gradle and Android integration workflow. Use `list_accounts` when an account handle is unknown. Model Context Protocol authentication only authorizes Tuist tools; Gradle requires separate `tuist auth whoami --url` authentication. Never continue a verification build after that check fails. Verify integrations through Tuist read-back tools before reporting success.
  """

  def server do
    EMCP.Server.new(
      name: "tuist",
      version: "1.24.0",
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
      @source_answer_instructions <> "\n" <> @agent_workflow_instructions
    else
      @agent_workflow_instructions
    end
  end

  defp codebase_search_enabled? do
    Environment.tuist_hosted?() and Environment.codebase_search_enabled?()
  end
end
