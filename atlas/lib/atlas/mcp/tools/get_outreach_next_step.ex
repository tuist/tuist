defmodule Atlas.MCP.Tools.GetOutreachNextStep do
  @moduledoc "Gets the current guided next step for an outreach contact."

  use Atlas.MCP.Tool,
    name: "get_outreach_next_step",
    schema: %{
      "type" => "object",
      "required" => ["contact_id"],
      "properties" => %{"contact_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Outreach.recommendation_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description, do: "Get Atlas's evidence-based suggested next action for an outreach contact."

  def execute(_conn, %{"contact_id" => contact_id}) do
    case Outreach.get_contact(contact_id) do
      nil -> {:error, "Outreach contact not found: #{contact_id}"}
      _contact -> {:ok, OutreachSerializer.recommendation_response(Outreach.current_recommendation(contact_id))}
    end
  end
end
