defmodule Tuist.MCP.Components.Tools.ListBazelInvocationLogs do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_invocation_logs",
    title: "List Bazel Invocation Logs",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "invocation_id" => %{"type" => "string", "description" => "The Bazel invocation identifier."},
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["account_handle", "project_handle", "invocation_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "logs" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.BazelInvocationLog.schema()
        },
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["logs", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelInvocationLog
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "List the sanitized logs captured for a Bazel invocation in execution order."

  def execute(_conn, %{"invocation_id" => invocation_id} = args, project) do
    {logs, meta} =
      Bazel.list_invocation_logs(project.id, invocation_id, %{
        order_by: [:sequence_number],
        order_directions: [:asc],
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      })

    {:ok,
     %{
       logs: Enum.map(logs, &BazelInvocationLog.json/1),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end
end
