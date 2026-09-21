defmodule Tuist.MCP.Components.Tools.ListCoverageBranches do
  @moduledoc """
  Every branch's head coverage against the default branch.
  """

  use Tuist.MCP.Tool,
    name: "list_coverage_branches",
    title: "List Coverage Branches",
    read_only_hint: true,
    feature: :coverage,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "days" => %{"type" => "integer", "description" => "How many days back to look (default 30)."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.branches_output()

  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "List every branch with a measured commit in the period, newest first, with its head commit's coverage (the union of the " <>
        "runs that measured it), the schemes that measured it, and the difference from the default branch's head in percentage " <>
        "points when both chain into their trends. Branch membership comes from the repository's Git graph. " <>
        "The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    days = max(Map.get(args, "days") || 30, 1)
    branches = History.branches(project, since: NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day))
    {:ok, %{branches: Enum.map(branches, &Report.branch/1)}}
  end
end
