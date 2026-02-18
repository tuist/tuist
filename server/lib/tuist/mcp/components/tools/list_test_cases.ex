defmodule Tuist.MCP.Components.Tools.ListTestCases do
  @moduledoc """
  List test cases for a project.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Tuist.MCP.Components.ToolSupport
  alias Tuist.MCP.Formatter
  alias Tuist.Tests

  @authorization_action :read
  @authorization_category :test

  schema do
    field :account_handle, :string,
      required: true,
      description: "The account handle (organization or user)."

    field :project_handle, :string,
      required: true,
      description: "The project handle."

    field :flaky, :boolean, description: "When true, returns only flaky test cases."
    field :quarantined, :boolean, description: "Filter by quarantined status."
    field :module_name, :string, description: "Filter by module name."
    field :name, :string, description: "Filter by test case name."
    field :suite_name, :string, description: "Filter by suite name."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(%{account_handle: account_handle, project_handle: project_handle} = arguments, frame) do
    with {:ok, project} <-
           ToolSupport.load_and_authorize_project_by_handle(
             account_handle,
             project_handle,
             frame,
             @authorization_action,
             @authorization_category,
             "You do not have access to project: #{account_handle}/#{project_handle}"
           ) do
      page = arguments |> Map.get(:page) |> integer_argument(1)
      page_size = arguments |> Map.get(:page_size) |> integer_argument(20) |> min(100)
      filters = build_filters(arguments)

      {test_cases, meta} =
        Tests.list_test_cases(project.id, %{
          filters: filters,
          order_by: [:last_ran_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
        test_cases:
          Enum.map(test_cases, fn test_case ->
            %{
              id: test_case.id,
              name: test_case.name,
              module_name: test_case.module_name,
              suite_name: test_case.suite_name,
              is_flaky: test_case.is_flaky,
              is_quarantined: test_case.is_quarantined,
              last_status: to_string(test_case.last_status),
              last_duration: test_case.last_duration,
              last_ran_at: Formatter.iso8601(test_case.last_ran_at, naive: :utc),
              avg_duration: test_case.avg_duration
            }
          end),
        pagination_metadata: %{
          has_next_page: meta.has_next_page?,
          has_previous_page: meta.has_previous_page?,
          total_count: meta.total_count,
          total_pages: meta.total_pages,
          current_page: meta.current_page,
          page_size: meta.page_size
        }
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp integer_argument(value, _default) when is_integer(value) and value > 0, do: value
  defp integer_argument(_value, default), do: default

  defp build_filters(arguments) do
    arguments
    |> Map.take([:flaky, :quarantined, :module_name, :name, :suite_name])
    |> Enum.reduce([], fn
      {:flaky, value}, filters -> maybe_add_filter(filters, :is_flaky, value)
      {:quarantined, value}, filters -> maybe_add_filter(filters, :is_quarantined, value)
      {field, value}, filters -> maybe_add_filter(filters, field, value)
    end)
    |> Enum.reverse()
  end

  defp maybe_add_filter(filters, _field, nil), do: filters

  defp maybe_add_filter(filters, field, true) when field in [:is_flaky, :is_quarantined],
    do: [%{field: field, op: :==, value: true} | filters]

  defp maybe_add_filter(filters, field, value), do: [%{field: field, op: :==, value: value} | filters]
end
