defmodule Atlas.MCP.Tools.ListProductTraces do
  use Atlas.MCP.Tool,
    name: "list_product_traces",
    schema: %{
      "type" => "object",
      "properties" => %{
        "kind" => %{
          "type" => "string",
          "enum" => [
            "pull_request_opened",
            "pull_request_merged",
            "pull_request_closed",
            "issue_opened",
            "issue_closed"
          ]
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "traces" => %{
          "type" => "array",
          "items" => Atlas.MCP.Serializers.Briefs.product_trace_schema()
        },
        "count" => %{"type" => "integer"}
      },
      "required" => ["traces", "count"],
      "additionalProperties" => false
    }

  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Product

  @impl EMCP.Tool
  def description do
    "List observed pull request and issue activity captured from configured GitHub repositories."
  end

  def execute(_conn, args) do
    {traces, _meta} = Product.list_traces(kind: args["kind"], page_size: Tool.page_size(args))
    {:ok, %{traces: Enum.map(traces, &BriefSerializer.product_trace/1), count: length(traces)}}
  end
end
