defmodule Tuist.MCP.Components.Tools.ListTestRunCoverageFiles do
  @moduledoc """
  A test run's files with their coverage, least covered first.
  """

  use Tuist.MCP.Tool,
    name: "list_test_run_coverage_files",
    title: "List Test Run Coverage Files",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."},
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."}
      },
      "required" => ["test_run_id"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.files_output()

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "List a test run's product files with their line coverage, least covered first: the poorly covered files to look at. " <>
        "Use get_test_run_coverage_file for one file's lines."

  def execute(conn, %{"test_run_id" => test_run_id} = args) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)

    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ),
         :ok <- MCPTool.require_feature(project, :coverage) do
      {files, count} = Coverage.list_files(project.id, run.id, page, page_size)
      total_pages = max(1, ceil(count / page_size))

      {:ok,
       %{
         files: Enum.map(files, &Report.file/1),
         pagination_metadata: %{
           has_next_page: page < total_pages,
           has_previous_page: page > 1,
           total_count: count,
           total_pages: total_pages,
           current_page: page,
           page_size: page_size
         }
       }}
    end
  end
end
