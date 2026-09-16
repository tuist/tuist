defmodule Tuist.MCP.Components.Tools.ListCoverageBranches do
  @moduledoc """
  Every branch's newest full-run coverage against the default branch.
  """

  use Tuist.MCP.Tool,
    name: "list_coverage_branches",
    title: "List Coverage Branches",
    read_only_hint: true,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "scheme" => %{
          "type" => "string",
          "description" =>
            "The scheme to report; by default the one with most full runs on the default branch. Figures are never pooled across schemes."
        },
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
      "List every branch's coverage from its newest full run of a scheme in the period, newest first, with the difference from " <>
        "the project's default branch in percentage points. Partial runs (tests skipped on purpose) never make a branch's figure. " <>
        "The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    days = max(Map.get(args, "days") || 30, 1)
    opts = [since: NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day)]

    scheme =
      Map.get(args, "scheme") ||
        case History.schemes(project.id, project.default_branch, opts) do
          [%{scheme: scheme} | _] -> scheme
          [] -> nil
        end

    branches = if scheme, do: History.branches(project, scheme, opts), else: []
    {:ok, %{scheme: scheme, branches: Enum.map(branches, &Report.branch/1)}}
  end
end
