defmodule Tuist.MCP.Components.Tools.GetCommitCoverage do
  @moduledoc """
  A commit's code coverage: the union of its runs, its measured set, targets and baseline.
  """

  use Tuist.MCP.Tool,
    name: "get_commit_coverage",
    title: "Get Commit Coverage",
    read_only_hint: true,
    feature: :coverage,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "git_commit_sha" => %{"type" => "string", "description" => "The commit SHA."}
      },
      "required" => ["account_handle", "project_handle", "git_commit_sha"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.commit_output()

  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Get a commit's code coverage: the union of every run that measured it (a line is covered when any run covered it), " <>
        "which schemes measured it and which only partially, whether its pipeline signalled completion, how many source files " <>
        "no run measured, its targets least covered first, and its baseline (the nearest measured ancestor of its merge base " <>
        "with the base branch) or why there is none. Use get_commit_coverage_comparison for the deltas, patch coverage and gaps. " <>
        "The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"git_commit_sha" => sha}, project) do
    case Commits.summary(project.id, sha) do
      nil -> {:error, "No run of commit #{sha} gathered coverage"}
      summary -> {:ok, Report.commit(project, summary, Commits.targets(project.id, sha))}
    end
  end
end
