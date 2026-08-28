defmodule Tuist.MCP.Components.Tools.ListBazelTestResults do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_test_results",
    title: "List Bazel Test Results",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "status" => %{"type" => "string", "description" => "Filter by test-target status."},
        "invocation_id" => %{"type" => "string", "description" => "Filter by Bazel invocation identifier."},
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "test_results" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.BazelTestResult.schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["test_results", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelTestResult
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "List Bazel test-target results emitted through the Build Event Protocol."

  def execute(_conn, args, project) do
    filters =
      [%{field: :project_id, op: :==, value: project.id}]
      |> maybe_append_status(Map.get(args, "status"))
      |> maybe_append_invocation_id(Map.get(args, "invocation_id"))

    {test_results, meta} =
      Bazel.list_test_results(project.id, %{
        filters: filters,
        order_by: [:finished_at],
        order_directions: [:desc],
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      })

    {:ok,
     %{
       test_results: Enum.map(test_results, &BazelTestResult.json/1),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp maybe_append_status(filters, status) when status in ["success", "failure", "flaky", "skipped"],
    do: filters ++ [%{field: :status, op: :==, value: status}]

  defp maybe_append_status(filters, _status), do: filters

  defp maybe_append_invocation_id(filters, invocation_id) when is_binary(invocation_id) and invocation_id != "",
    do: filters ++ [%{field: :invocation_id, op: :==, value: invocation_id}]

  defp maybe_append_invocation_id(filters, _invocation_id), do: filters
end
