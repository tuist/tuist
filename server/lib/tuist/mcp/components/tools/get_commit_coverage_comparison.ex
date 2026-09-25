defmodule Tuist.MCP.Components.Tools.GetCommitCoverageComparison do
  @moduledoc """
  A commit's coverage against its baseline: deltas, patch coverage, gaps.
  """

  use Tuist.MCP.Tool,
    name: "get_commit_coverage_comparison",
    title: "Get Commit Coverage Comparison",
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
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.comparison()

  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Compare a commit's coverage with its baseline, the nearest measured ancestor of its merge base with the base branch " <>
        "(its first parent for a commit on the base branch), walked first-parent through the repository's Git graph so the " <>
        "branch's own earlier pushes are never the baseline: the total delta when both commits measured the same schemes fully, " <>
        "each scheme's own totals, the per-target and per-file deltas, the patch coverage of the changed lines with the files not " <>
        "counted and why, and the gaps: changed files no test executed. When no baseline can be resolved the comparison says why " <>
        "rather than comparing with another commit. The account_handle and project_handle can be extracted from a Tuist " <>
        "dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"git_commit_sha" => sha}, project) do
    case Commits.summary(project.id, sha) do
      nil -> {:error, "No run of commit #{sha} gathered coverage"}
      _summary -> {:ok, Report.comparison(Comparison.compare(project, Comparison.from_commit(project, sha)))}
    end
  end
end
