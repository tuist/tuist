defmodule Tuist.MCP.Components.Tools.ListTestCases do
  @moduledoc """
  List test cases for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
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
  def execute(arguments, frame) do
    with {:ok, project} <-
           ToolSupport.resolve_and_authorize_project(
             arguments,
             frame,
             @authorization_action,
             @authorization_category
           ) do
      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)
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
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

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
