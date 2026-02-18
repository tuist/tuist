defmodule Tuist.MCP.Components.Tools.ListTestCases do
  @moduledoc """
  List test cases for a project.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.MCP.Error
  alias Hermes.Server.Response
  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Formatter
  alias Tuist.Projects
  alias Tuist.Tests

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
    subject = Authorization.authenticated_subject(frame.assigns)
    project = Projects.get_project_by_account_and_project_handles(account_handle, project_handle)

    cond do
      is_nil(project) ->
        invalid_params("Project not found: #{account_handle}/#{project_handle}", frame)

      not Authorization.authorize(subject, :read, project, :test) ->
        invalid_params("You do not have access to project: #{account_handle}/#{project_handle}", frame)

      true ->
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
    []
    |> maybe_add_filter(:is_flaky, Map.get(arguments, :flaky))
    |> maybe_add_filter(:is_quarantined, Map.get(arguments, :quarantined))
    |> maybe_add_filter(:module_name, Map.get(arguments, :module_name))
    |> maybe_add_filter(:name, Map.get(arguments, :name))
    |> maybe_add_filter(:suite_name, Map.get(arguments, :suite_name))
  end

  defp maybe_add_filter(filters, _field, nil), do: filters

  defp maybe_add_filter(filters, field, true) when field in [:is_flaky, :is_quarantined],
    do: filters ++ [%{field: field, op: :==, value: true}]

  defp maybe_add_filter(filters, field, value), do: filters ++ [%{field: field, op: :==, value: value}]

  defp invalid_params(message, frame) do
    {:error, Error.protocol(:invalid_params, %{message: message}), frame}
  end
end
