defmodule Atlas.MCP.Tools.ListBriefs do
  use Atlas.MCP.Tool,
    name: "list_briefs",
    schema: %{
      "type" => "object",
      "properties" => %{
        "cadence" => %{"type" => "string", "enum" => ["daily", "weekly"]},
        "status" => %{
          "type" => "string",
          "enum" => ["draft", "material", "immaterial", "posted", "failed"]
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "briefs" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Briefs.brief_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["briefs", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Briefs
  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List persisted daily and weekly attention briefs for leadership."

  def execute(conn, args) do
    with :ok <- Tool.authorize_executive(conn, "Leadership brief tools") do
      {briefs, _meta} =
        Briefs.list_briefs(
          cadence: args["cadence"],
          status: args["status"],
          page_size: Tool.page_size(args)
        )

      {:ok, %{briefs: Enum.map(briefs, &BriefSerializer.brief/1), count: length(briefs)}}
    end
  end
end
