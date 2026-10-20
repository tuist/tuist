defmodule Atlas.MCP.Tools.ListGTMOpportunities do
  @moduledoc """
  Lists company-level GTM outreach opportunities.
  """

  use Atlas.MCP.Tool,
    name: "list_gtm_opportunities",
    schema: %{
      "type" => "object",
      "properties" => %{
        "status" => %{
          "type" => "string",
          "enum" => ["new", "reviewed", "qualified", "rejected", "converted"]
        },
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.GTM.list_response_schema(
        :gtm_opportunities,
        Atlas.MCP.Serializers.GTM.opportunity_schema()
      )

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List company-level GTM outreach opportunities with scores and evidence counts."

  def execute(_conn, args) do
    opportunities =
      [status: args["status"], limit: Tool.page_size(args)]
      |> GTM.list_gtm_opportunities()
      |> Enum.map(&GTMSerializer.opportunity/1)

    {:ok, GTMSerializer.list_response(:gtm_opportunities, opportunities)}
  end
end
