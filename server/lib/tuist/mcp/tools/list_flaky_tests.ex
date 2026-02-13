defmodule Tuist.MCP.Tools.ListFlakyTests do
  @moduledoc false

  alias Tuist.MCP.Authorization
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
    case Authorization.get_authorized_project(account_handle, project_handle, subject) do
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
                last_flaky_at: format_datetime(tc.last_flaky_at)
              }
            end),
          pagination: %{
            total_count: meta.total_count,
            total_pages: meta.total_pages,
            current_page: meta.current_page,
            page_size: meta.page_size
          }
        }

        {:ok, %{content: [%{type: "text", text: Jason.encode!(data)}]}}

      {:error, code, message} ->
        {:error, code, message}
    end
  end

  def call(_arguments, _subject) do
    {:error, -32_602, "Missing required parameters: account_handle, project_handle."}
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%NaiveDateTime{} = dt) do
    dt |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(other), do: to_string(other)
end
