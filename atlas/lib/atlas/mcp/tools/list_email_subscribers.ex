defmodule Atlas.MCP.Tools.ListEmailSubscribers do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "list_email_subscribers",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => ["pending", "subscribed", "unsubscribed"]},
        "source" => %{"type" => "string"},
        "page" => %{"type" => "integer", "minimum" => 1},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.GTMEmail.list_schema(:subscribers, Atlas.MCP.Serializers.GTMEmail.subscriber_schema(), true)

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTMEmail

  @impl EMCP.Tool
  def description,
    do: "List Atlas email subscribers, optionally filtered by status, source, or a name and email search."

  def execute(_conn, args) do
    {subscribers, metadata} =
      GTM.list_email_subscribers(
        query: args["query"],
        status: args["status"],
        source: args["source"],
        page: args["page"],
        page_size: args["page_size"]
      )

    serialized = Enum.map(subscribers, &GTMEmail.subscriber/1)
    {:ok, %{subscribers: serialized, count: length(serialized), total_count: metadata.total_count}}
  end
end
