defmodule Tuist.MCP.Components.Tools.GetTestRunCoverageComparison do
  @moduledoc """
  A test run's coverage against its baseline: deltas, patch coverage, gaps.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_coverage_comparison",
    title: "Get Test Run Coverage Comparison",
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
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.comparison()

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Compare a test run's coverage with its baseline (the newest full run of the same scheme on the base branch, at the merge base " <>
        "or the nearest ancestor of it): the total delta (full runs only; a run that skipped tests has none), the per-target and " <>
        "per-file deltas, the patch coverage of the changed lines with the files not counted and why, and the gaps: changed files " <>
        "no test executed. When no baseline can be resolved the comparison says why rather than comparing with another run."

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
        summary -> {:ok, Report.comparison(Comparison.compare(project, run, run_summary: summary))}
      end
    end
  end
end
