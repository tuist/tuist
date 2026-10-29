defmodule Tuist.MCP.Components.Tools.ListBazelCacheEvents do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_cache_events",
    title: "List Bazel Cache Events",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "invocation_id" => %{"type" => "string", "description" => "Filter by Bazel invocation identifier."},
        "outcome" => %{"type" => "string", "description" => "Filter by hit, miss, or write."},
        "operation" => %{
          "type" => "string",
          "enum" => ["action_cache", "cas"],
          "description" => "Filter by action cache or content-addressable storage operation."
        },
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["account_handle", "project_handle"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "cache_events" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.BazelCacheEvent.schema()
        },
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["cache_events", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.BazelCacheEvent
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.ReapiCache

  @impl EMCP.Tool
  def description, do: "List the raw Bazel remote-cache observations for a project."

  def execute(_conn, args, project) do
    filters =
      [%{field: :project_id, op: :==, value: project.id}]
      |> maybe_append_filter(:invocation_id, Map.get(args, "invocation_id"))
      |> maybe_append_outcome(Map.get(args, "outcome"))
      |> maybe_append_operation(Map.get(args, "operation"))

    {events, meta} =
      ReapiCache.list_cache_events(project.id, %{
        filters: filters,
        order_by: [:inserted_at],
        order_directions: [:desc],
        page: MCPTool.page(args),
        page_size: MCPTool.page_size(args)
      })

    {:ok,
     %{
       cache_events: Enum.map(events, &BazelCacheEvent.json/1),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end

  defp maybe_append_filter(filters, _field, nil), do: filters
  defp maybe_append_filter(filters, _field, ""), do: filters
  defp maybe_append_filter(filters, field, value), do: filters ++ [%{field: field, op: :==, value: value}]

  defp maybe_append_outcome(filters, outcome) when outcome in ["hit", "miss", "write"],
    do: filters ++ [%{field: :outcome, op: :==, value: outcome}]

  defp maybe_append_outcome(filters, _outcome), do: filters

  defp maybe_append_operation(filters, operation) when operation in ["action_cache", "cas"],
    do: filters ++ [%{field: :operation, op: :==, value: operation}]

  defp maybe_append_operation(filters, _operation), do: filters
end
