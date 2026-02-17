defmodule Tuist.MCP.Tools.ListTestCases do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Content
  alias Tuist.MCP.Errors
  alias Tuist.MCP.Formatter
  alias Tuist.Tests

  def name, do: "list_test_cases"

  def definition do
    %{
      name: name(),
      description: "List test cases for a project.",
      inputSchema: %{
        type: "object",
        properties: %{
          account_handle: %{type: "string", description: "The account handle (organization or user)."},
          project_handle: %{type: "string", description: "The project handle."},
          flaky: %{type: "boolean", description: "When true, returns only flaky test cases."},
          quarantined: %{type: "boolean", description: "Filter by quarantined status."},
          module_name: %{type: "string", description: "Filter by module name."},
          name: %{type: "string", description: "Filter by test case name."},
          suite_name: %{type: "string", description: "Filter by suite name."},
          page: %{type: "integer", description: "Page number (default: 1)."},
          page_size: %{type: "integer", description: "Results per page (default: 20, max: 100)."}
        },
        required: ["account_handle", "project_handle"]
      }
    }
  end

  def call(%{"account_handle" => account_handle, "project_handle" => project_handle} = arguments, subject) do
    case Authorization.get_authorized_project(:test_read, account_handle, project_handle, subject) do
      {:ok, project} ->
        page = integer_argument(arguments, "page", 1)
        page_size = arguments |> integer_argument("page_size", 20) |> min(100)
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
            Enum.map(test_cases, fn tc ->
              %{
                id: tc.id,
                name: tc.name,
                module_name: tc.module_name,
                suite_name: tc.suite_name,
                is_flaky: tc.is_flaky,
                is_quarantined: tc.is_quarantined,
                last_status: to_string(tc.last_status),
                last_duration: tc.last_duration,
                last_ran_at: Formatter.iso8601(tc.last_ran_at, naive: :utc),
                avg_duration: tc.avg_duration
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

        Content.ok_json(data)

      {:error, code, message} ->
        {:error, code, message}
    end
  end

  def call(_arguments, _subject) do
    Errors.invalid_params("Missing required parameters: account_handle, project_handle.")
  end

  defp integer_argument(arguments, key, default) do
    case Map.get(arguments, key, default) do
      value when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end

  defp build_filters(arguments) do
    []
    |> maybe_add_filter(:is_flaky, Map.get(arguments, "flaky"))
    |> maybe_add_filter(:is_quarantined, Map.get(arguments, "quarantined"))
    |> maybe_add_filter(:module_name, Map.get(arguments, "module_name"))
    |> maybe_add_filter(:name, Map.get(arguments, "name"))
    |> maybe_add_filter(:suite_name, Map.get(arguments, "suite_name"))
  end

  defp maybe_add_filter(filters, _field, nil), do: filters

  defp maybe_add_filter(filters, field, true) when field in [:is_flaky, :is_quarantined],
    do: filters ++ [%{field: field, op: :==, value: true}]

  defp maybe_add_filter(filters, field, value), do: filters ++ [%{field: field, op: :==, value: value}]
end
