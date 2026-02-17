defmodule Tuist.MCP.Tools.ListFlakyTests do
  @moduledoc false

  alias Tuist.MCP.Authorization
  alias Tuist.MCP.Content
  alias Tuist.MCP.Errors
  alias Tuist.MCP.Formatter
  alias Tuist.Tests

  def name, do: "list_flaky_tests"

  def definition do
    %{
      name: name(),
      description: "List flaky test cases for a project.",
      inputSchema: %{
        type: "object",
        properties: %{
          account_handle: %{type: "string", description: "The account handle (organization or user)."},
          project_handle: %{type: "string", description: "The project handle."},
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
        page = Map.get(arguments, "page", 1)
        page_size = min(Map.get(arguments, "page_size", 20), 100)

        {flaky_tests, meta} =
          Tests.list_flaky_test_cases(project.id, %{
            page: page,
            page_size: page_size
          })

        data = %{
          flaky_tests:
            Enum.map(flaky_tests, fn tc ->
              %{
                id: tc.id,
                name: tc.name,
                module_name: tc.module_name,
                suite_name: tc.suite_name,
                flaky_runs_count: tc.flaky_runs_count,
                last_flaky_at: Formatter.iso8601(tc.last_flaky_at)
              }
            end),
          pagination: %{
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
end
