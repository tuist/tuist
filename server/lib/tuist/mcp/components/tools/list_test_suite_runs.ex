defmodule Tuist.MCP.Components.Tools.ListTestSuiteRuns do
  @moduledoc """
  List test suite runs for a specific test run, optionally filtered by module. The test_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/tests/test-runs/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  schema do
    field :test_run_id, :string,
      required: true,
      description: "The ID of the test run."

    field :module_name, :string, description: "Filter suites by module name."
    field :status, :string, description: "Filter by status: success, failure, or skipped."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(%{test_run_id: test_run_id} = arguments, frame) do
    with {:ok, run} <-
           ToolSupport.load_resource(
             Tests.get_test(test_run_id),
             "Test run not found: #{test_run_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             run.project_id,
             @authorization_action,
             @authorization_category
           ) do
      filters = [%{field: :test_run_id, op: :==, value: test_run_id}]

      filters =
        Enum.reduce([:status], filters, fn field, acc ->
          case Map.get(arguments, field) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)

      {suites, meta} =
        Tests.list_test_suite_runs(%{
          filters: filters,
          order_by: [:duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      suites =
        case Map.get(arguments, :module_name) do
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

      {:reply, Response.json(Response.tool(), data), frame}
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
