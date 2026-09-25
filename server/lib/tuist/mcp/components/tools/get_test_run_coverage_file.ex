defmodule Tuist.MCP.Components.Tools.GetTestRunCoverageFile do
  @moduledoc """
  One file's coverage in a test run, line by line.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_coverage_file",
    title: "Get Test Run Coverage File",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."},
        "path" => %{"type" => "string", "description" => "The file's repository-relative path."}
      },
      "required" => ["test_run_id", "path"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.file_detail()

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Get one file's coverage in a test run: every executable line with its execution count, the ranges of lines no test ran, " <>
        "and its functions. Test code is not reported."

  def execute(conn, %{"test_run_id" => test_run_id, "path" => path}) do
    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ),
         :ok <- MCPTool.require_feature(project, :coverage) do
      case Coverage.file_detail(project.id, run.id, path) do
        nil -> {:error, "The test run has no coverage for #{path}"}
        detail -> {:ok, Report.file_detail(detail)}
      end
    end
  end
end
