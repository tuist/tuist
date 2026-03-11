defmodule Tuist.MCP.Components.Tools.ListTestModuleRuns do
  @moduledoc """
  List test module runs for a specific test run. The test_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/tests/test-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  @impl EMCP.Tool
  def name, do: "list_test_module_runs"

  @impl EMCP.Tool
  def description,
    do:
      "List test module runs for a specific test run. The test_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/tests/test-runs/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test run."
        },
        "status" => %{
          "type" => "string",
          "description" => "Filter by status: success or failure."
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
  end

  @impl EMCP.Tool
  def call(conn, %{"test_run_id" => test_run_id} = args) do
    with {:ok, run} <-
           ToolSupport.load_resource(
             Tests.get_test(test_run_id),
             "Test run not found: #{test_run_id}"
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             conn.assigns,
             run.project_id,
             @authorization_action,
             @authorization_category
           ) do
      filters = [%{field: :test_run_id, op: :==, value: test_run_id}]

      filters =
        case Map.get(args, "status") do
          nil -> filters
          status -> filters ++ [%{field: :status, op: :==, value: status}]
        end

      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)

      {modules, meta} =
        Tests.list_test_module_runs(%{
          filters: filters,
          order_by: [:duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
        modules:
          Enum.map(modules, fn mod ->
            %{
              name: mod.name,
              status: to_string(mod.status),
              is_flaky: mod.is_flaky,
              duration: mod.duration,
              test_suite_count: mod.test_suite_count,
              test_case_count: mod.test_case_count,
              avg_test_case_duration: mod.avg_test_case_duration
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end
