defmodule Tuist.MCP.Components.Tools.ListTestSuiteRuns do
  @moduledoc """
  List test suite runs for a specific test run, optionally filtered by module. The test_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/tests/test-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  @impl EMCP.Tool
  def name, do: "list_test_suite_runs"

  @impl EMCP.Tool
  def description,
    do:
      "List test suite runs for a specific test run, optionally filtered by module. The test_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/tests/test-runs/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{
          "type" => "string",
          "description" => "The ID of the test run."
        },
        "module_name" => %{
          "type" => "string",
          "description" => "Filter suites by module name."
        },
        "status" => %{
          "type" => "string",
          "description" => "Filter by status: success, failure, or skipped."
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
        Enum.reduce(["status"], filters, fn key, acc ->
          case Map.get(args, key) do
            nil -> acc
            value -> acc ++ [%{field: String.to_existing_atom(key), op: :==, value: value}]
          end
        end)

      page = ToolSupport.page(args)
      page_size = ToolSupport.page_size(args)

      {suites, meta} =
        Tests.list_test_suite_runs(%{
          filters: filters,
          order_by: [:duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      suites =
        case Map.get(args, "module_name") do
          nil ->
            suites

          module_name ->
            module_ids = get_module_run_ids(test_run_id, module_name)
            Enum.filter(suites, &(&1.test_module_run_id in module_ids))
        end

      data = %{
        suites:
          Enum.map(suites, fn suite ->
            %{
              name: suite.name,
              status: to_string(suite.status),
              is_flaky: suite.is_flaky,
              duration: suite.duration,
              test_case_count: suite.test_case_count,
              avg_test_case_duration: suite.avg_test_case_duration
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp get_module_run_ids(test_run_id, module_name) do
    {modules, _meta} =
      Tests.list_test_module_runs(%{
        filters: [
          %{field: :test_run_id, op: :==, value: test_run_id},
          %{field: :name, op: :==, value: module_name}
        ],
        page: 1,
        page_size: 10
      })

    Enum.map(modules, & &1.id)
  end
end
