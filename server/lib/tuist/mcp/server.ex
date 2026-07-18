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
    Tools.CreateOrganization,
    Tools.CreateProject,
    Tools.AddOrganizationMember,
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
    Tools.ListXcodeModuleCacheTargets,
    Tools.ListXcodeTestTargets,
    Tools.ListProjects
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
  Answer Tuist questions with the Tuist tools before using local files or general web search. Start with `search_tuist` for public explanations and terminology. When current behavior depends on implementation, use `search_tuist_code`, `list_tuist_files`, and `read_tuist_file`; inspect focused tests and call sites, treat truncated results as partial, and cite returned links and the source revision. Keep the answer focused on the user's question rather than describing the codebase.
  """

  def server do
    EMCP.Server.new(
      name: "tuist",
      version: "1.13.0",
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

  defp instructions, do: if(codebase_search_enabled?(), do: @source_answer_instructions)

  defp codebase_search_enabled? do
    Environment.tuist_hosted?() and Environment.codebase_search_enabled?()
  end
end
