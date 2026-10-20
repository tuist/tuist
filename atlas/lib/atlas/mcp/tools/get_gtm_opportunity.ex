defmodule Atlas.MCP.Tools.GetGTMOpportunity do
  @moduledoc """
  Gets a GTM outreach opportunity with signals and suggested contacts.
  """

  use Atlas.MCP.Tool,
    name: "get_gtm_opportunity",
    schema: %{
      "type" => "object",
      "required" => ["opportunity_id"],
      "properties" => %{
        "opportunity_id" => %{"type" => "string"}
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"gtm_opportunity" => Atlas.MCP.Serializers.GTM.opportunity_with_details_schema()},
      "required" => ["gtm_opportunity"],
      "additionalProperties" => false
    }

  alias Atlas.GTM
  alias Atlas.MCP.Serializers.GTM, as: GTMSerializer

  @impl EMCP.Tool
  def description, do: "Get a GTM outreach opportunity with its evidence signals and suggested contacts."

  def execute(_conn, %{"opportunity_id" => id}) do
    case GTM.get_gtm_opportunity(id) do
      nil -> {:error, "GTM opportunity not found."}
      opportunity -> {:ok, %{gtm_opportunity: GTMSerializer.opportunity_with_details(opportunity)}}
    end
  end
end
