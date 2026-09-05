defmodule Tuist.MCP.Components.Tools.ListBazelInvocations do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_invocations",
    title: "List Bazel Invocations",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "status" => %{"type" => "string", "description" => "Filter by success or failure."},
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "invocations" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.BazelInvocation.schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["invocations", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelInvocation
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "List Bazel invocations and their correlated remote-cache totals for a project."

  def execute(_conn, args, project) do
    filters = maybe_append_status([%{field: :project_id, op: :==, value: project.id}], Map.get(args, "status"))

    {invocations, meta} =
      Bazel.list_invocations(project.id, %{
        filters: filters,
        order_by: [:finished_at],
        order_directions: [:desc],
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      })

    {:ok,
     %{
       invocations: Enum.map(invocations, &BazelInvocation.json/1),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp maybe_append_status(filters, status) when status in ["success", "failure"],
    do: filters ++ [%{field: :status, op: :==, value: status}]

  defp maybe_append_status(filters, _status), do: filters
end
