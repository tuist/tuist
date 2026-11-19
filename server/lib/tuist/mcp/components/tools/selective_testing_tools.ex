defmodule Tuist.MCP.Components.Tools.SelectiveTestingTools do
  @moduledoc """
  What the tools reading a test run's coverage-based selection share: their
  arguments and the run's loading. The reads and their shapes are the API's
  (`Tuist.Tests.Selections.Query`).
  """

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  def properties do
    %{
      "test_run_id" => %{"type" => "string", "description" => "The ID of the test run, or a Tuist dashboard URL."},
      "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
      "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."}
    }
  end

  def with_test_run(conn, test_run_id, fun) do
    test_run_id = MCPTool.resource_id(test_run_id)

    with {:ok, test_run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      fun.(test_run, project)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListSelectiveTestingTests do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_selective_testing_tests",
    title: "List Selective Testing Tests",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(Tuist.MCP.Components.Tools.SelectiveTestingTools.properties(), %{
          "decision" => %{
            "type" => "string",
            "enum" => ["selected", "skipped"],
            "description" => "Only the selected or only the skipped tests."
          },
          "reason" => %{
            "type" => "string",
            "description" =>
              "Only the tests with this reason, such as `impacted`, `test_file_changed`, `unaffected`, `module_skipped` or a fallback's reason such as `tracked_file_changed`."
          },
          "search" => %{"type" => "string", "description" => "Part of the module, suite or test name."}
        }),
      "required" => ["test_run_id"]
    },
    output_schema:
      Tuist.MCP.Tool.json_schema(Tuist.Tests.Selections.Schemas.tests(Tuist.MCP.Tool.pagination_metadata_schema()))

  alias Tuist.MCP.Components.Tools.SelectiveTestingTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests.Selections.Query

  @impl EMCP.Tool
  def description,
    do:
      "List the tests a test run's coverage-based selection decided, selected and skipped, each with the reason for its decision (a fallback's reason when coverage couldn't decide), the changed file that selected it, its shard and its outcome in the run. Empty when the run had no coverage-based selection. The test_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/tests/test-runs/{id}."

  def execute(conn, %{"test_run_id" => test_run_id} = args) do
    SelectiveTestingTools.with_test_run(conn, test_run_id, fn test_run, _project ->
      Query.tests(test_run,
        decision: Map.get(args, "decision"),
        reason: Map.get(args, "reason"),
        search: Map.get(args, "search"),
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      )
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.ListSelectiveTestingChangedFiles do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_selective_testing_changed_files",
    title: "List Selective Testing Changed Files",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Tuist.MCP.Components.Tools.SelectiveTestingTools.properties(), "search", %{
          "type" => "string",
          "description" => "Part of the file's path."
        }),
      "required" => ["test_run_id"]
    },
    output_schema:
      Tuist.MCP.Tool.json_schema(
        Tuist.Tests.Selections.Schemas.changed_files(Tuist.MCP.Tool.pagination_metadata_schema())
      )

  alias Tuist.MCP.Components.Tools.SelectiveTestingTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests.Selections.Query

  @impl EMCP.Tool
  def description,
    do:
      "List the files that changed between a test run's coverage-based selection baseline and its checkout, the ones that selected the most tests first, each with whether it's a tracked file whose change makes selection fall back. Empty when the run had no baseline, ran from a dirty checkout, or its diff expired. The test_run_id can also be a Tuist dashboard URL."

  def execute(conn, %{"test_run_id" => test_run_id} = args) do
    SelectiveTestingTools.with_test_run(conn, test_run_id, fn test_run, project ->
      Query.changed_files(project, test_run,
        search: Map.get(args, "search"),
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      )
    end)
  end
end
