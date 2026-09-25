defmodule Tuist.MCP.Components.Tools.ListCoverageHistory do
  @moduledoc """
  A branch's commits with their coverage, newest first, measured or not.
  """

  use Tuist.MCP.Tool,
    name: "list_coverage_history",
    title: "List Coverage History",
    read_only_hint: true,
    feature: :coverage,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "branch" => %{"type" => "string", "description" => "The branch; the default branch by default."},
        "days" => %{"type" => "integer", "description" => "How many days back to look (default 30)."},
        "limit" => %{"type" => "integer", "description" => "How many commits from the head (default 100, at most 500)."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.history_output()

  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "List a branch's commits newest first, from the repository's Git graph (first-parent from the branch's head), with the " <>
        "coverage of the ones some run measured: this is where a drop is found, since unmeasured commits between two measured " <>
        "ones are listed rather than blamed on the later one. A measured commit chains into the trend when its pipeline " <>
        "signalled completion or it measured the same schemes as the previous chained commit. Use get_commit_coverage_comparison " <>
        "on a commit to see what changed. The account_handle and project_handle can be extracted from a Tuist dashboard URL: " <>
        "#{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    branch = Map.get(args, "branch") || project.default_branch
    days = max(Map.get(args, "days") || 30, 1)
    limit = args |> Map.get("limit") |> Kernel.||(100) |> max(1) |> min(500)

    history =
      History.branch_history(project, branch,
        since: NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day),
        limit: limit
      )

    {:ok,
     %{
       branch: branch,
       ordered_by: Atom.to_string(history.ordered_by),
       commits: Enum.map(history.commits, &Report.history_commit/1)
     }}
  end
end
