defmodule Tuist.MCP.Components.Tools.GetTestRunCoverage do
  @moduledoc """
  A test run's code coverage: totals, targets, Git history and baseline.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_coverage",
    title: "Get Test Run Coverage",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."}
      },
      "required" => ["test_run_id"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.run_output()

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Get a test run's code coverage: line coverage over its product files (test code excluded), its targets least covered first, " <>
        "where the run sits in Git history (base branch, merge base, how the history was collected), and its baseline: the newest " <>
        "full run of the same scheme on the base branch at the merge base or the nearest ancestor of it, or why there is none. " <>
        "Use list_test_run_coverage_files for the files, get_test_run_coverage_comparison for the deltas, patch coverage and gaps."

  def execute(conn, %{"test_run_id" => test_run_id}) do
    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ),
         :ok <- MCPTool.require_feature(project, :coverage) do
      case Coverage.run_summary(project.id, run.id) do
        nil -> {:error, "The test run gathered no coverage: #{test_run_id}"}
        summary -> {:ok, Report.run(project, run, summary)}
      end
    end
  end
end
