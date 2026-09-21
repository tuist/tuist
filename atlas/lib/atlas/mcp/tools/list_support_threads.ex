defmodule Atlas.MCP.Tools.ListSupportThreads do
  use Atlas.MCP.Tool,
    name: "list_support_threads",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{"type" => "string", "enum" => ["open", "waiting", "resolved"]},
        "query" => %{"type" => "string"},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "threads" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Support.thread_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["threads", "count"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Support, as: SupportSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Support

  @impl EMCP.Tool
  def description, do: "List customer support conversations, most recently active first."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "support:read", "Support tools") do
      {threads, _meta} =
        Support.list_threads(
          status: args["status"],
          query: args["query"],
          page_size: Tool.page_size(args)
        )

      {:ok, %{threads: Enum.map(threads, &SupportSerializer.thread/1), count: length(threads)}}
    end
  end
end
