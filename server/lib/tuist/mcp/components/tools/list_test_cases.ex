defmodule Tuist.MCP.Components.Tools.ListTestCases do
  @moduledoc """
  List test cases for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: https://tuist.dev/{account_handle}/{project_handle}.
  """

  use Tuist.MCP.Tool,
    name: "list_test_cases",
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        },
        "flaky" => %{
          "type" => "boolean",
          "description" => "When true, returns only flaky test cases."
        },
        "state" => %{
          "type" => "string",
          "enum" => ["enabled", "muted", "skipped"],
          "description" =>
            ~s{Filter by test case state. "muted" tests still run but their failures don't fail the build; "skipped" tests are excluded from execution entirely. Both replace the legacy "quarantined" concept.}
        },
        "module_name" => %{
          "type" => "string",
          "description" => "Filter by module name."
        },
        "name" => %{
          "type" => "string",
          "description" => "Filter by test case name."
        },
        "suite_name" => %{
          "type" => "string",
          "description" => "Filter by suite name."
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
      "required" => ["account_handle", "project_handle"]
    }

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests

  @impl EMCP.Tool
  def description,
    do:
      "List test cases for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    filters = build_filters(args)

    # `:id` tiebreaker keeps paginated results stable when many test cases
    # share the same `:last_ran_at`.
    {test_cases, meta} =
      Tests.list_test_cases(project.id, %{
        filters: filters,
        order_by: [:last_ran_at, :id],
        order_directions: [:desc, :asc],
        page: page,
        page_size: page_size
      })

    {:ok,
     %{
       test_cases:
         Enum.map(test_cases, fn test_case ->
           %{
             id: test_case.id,
             name: test_case.name,
             module_name: test_case.module_name,
             suite_name: test_case.suite_name,
             is_flaky: test_case.is_flaky,
             state: test_case.state || "enabled",
             last_status: to_string(test_case.last_status),
             last_duration: test_case.last_duration,
             last_ran_at: Formatter.iso8601(test_case.last_ran_at, naive: :utc),
             avg_duration: test_case.avg_duration
           }
         end),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp build_filters(args) do
    [
      {"flaky", :is_flaky},
      {"state", :state},
      {"module_name", :module_name},
      {"name", :name},
      {"suite_name", :suite_name}
    ]
    |> Enum.reduce([], fn {key, field}, filters ->
      case {key, Map.get(args, key)} do
        {_, nil} -> filters
        {"flaky", true} -> [%{field: :is_flaky, op: :==, value: true} | filters]
        {_, value} -> [%{field: field, op: :==, value: value} | filters]
      end
    end)
    |> Enum.reverse()
  end
end
