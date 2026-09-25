defmodule Tuist.MCP.Components.Tools.GetPullRequestCoverage do
  @moduledoc """
  A pull request's coverage against its baseline.
  """

  use Tuist.MCP.Tool,
    name: "get_pull_request_coverage",
    title: "Get Pull Request Coverage",
    read_only_hint: true,
    feature: :coverage,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "pull_request_number" => %{"type" => "integer", "description" => "The pull request number."},
        "git_commit_sha" => %{"type" => "string", "description" => "The commit to compare; the newest by default."}
      },
      "required" => ["account_handle", "project_handle", "pull_request_number"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.pull_request_output()

  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Get a pull request's code coverage: every commit of it that gathered coverage, newest first, and the comparison of one of them " <>
        "(the newest, or git_commit_sha) with its baseline, the nearest measured ancestor of its merge base with the base branch: " <>
        "total delta when both measured the same schemes fully, each scheme's own totals, per-target and per-file deltas, patch " <>
        "coverage of the changed lines, and the gaps. The account_handle and project_handle can be extracted from a Tuist " <>
        "dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"pull_request_number" => number} = args, project) do
    commits = History.pull_request_commits(project.id, number)
    selected = Enum.find(commits, List.first(commits), &(&1.git_commit_sha == Map.get(args, "git_commit_sha")))

    case selected do
      nil ->
        {:error, "No test run of pull request ##{number} gathered coverage"}

      selected ->
        {:ok,
         %{
           pull_request_number: number,
           commits: Enum.map(commits, &Report.pull_request_commit/1),
           comparison:
             Report.comparison(Comparison.compare(project, Comparison.from_commit(project, selected.git_commit_sha)))
         }}
    end
  end
end
