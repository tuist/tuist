defmodule Tuist.MCP.Components.Tools.ListXcodeSelectiveTestingTargets do
  @moduledoc """
  List Xcode test targets with their selective testing status (hit/miss) and hash for a given test run. The test_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/tests/test-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_selective_testing_targets",
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test run."
        },
        "hit_status" => %{
          "type" => "string",
          "description" => "Filter by selective testing status: miss, local, or remote."
        },
        "page" => %{
          "type" => "integer",
          "description" => "Page number (default: 1)."
        },
        "page_size" => %{
          "type" => "integer",
          "description" => "Results per page (default: 20, max: 100)."
        }
      },
      "required" => ["test_run_id"]
    }

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Xcode

  @impl EMCP.Tool
  def description,
    do:
      "List Xcode test targets with their selective testing status (hit/miss) and hash for a given test run. The test_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/tests/test-runs/{id}."

  def execute(conn, %{"test_run_id" => test_run_id} = args) do
    with {:ok, run, _project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      page = MCPTool.page(args)
      page_size = MCPTool.page_size(args)

      flop_params = maybe_add_filter(%{page: page, page_size: page_size}, args)

      {analytics, meta} = Xcode.selective_testing_analytics(run, flop_params)

      {:ok,
       %{
         targets:
           Enum.map(analytics.test_modules, fn target ->
             %{
               name: target.name,
               hit_status: to_string(target.selective_testing_hit),
               hash: target.selective_testing_hash
             }
           end),
         pagination_metadata: MCPTool.pagination_metadata(meta)
       }}
    end
  end

  defp maybe_add_filter(flop_params, args) do
    case Map.get(args, "hit_status") do
      nil ->
        flop_params

      status ->
        Map.put(flop_params, :filters, [
          %{field: :selective_testing_hit, op: :==, value: status}
        ])
    end
  end
end
