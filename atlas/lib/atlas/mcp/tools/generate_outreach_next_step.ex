defmodule Atlas.MCP.Tools.GenerateOutreachNextStep do
  @moduledoc "Generates one evidence-based guided next step for an outreach contact."

  use Atlas.MCP.Tool,
    name: "generate_outreach_next_step",
    schema: %{
      "type" => "object",
      "required" => ["contact_id"],
      "properties" => %{"contact_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Outreach.recommendation_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description do
    "Analyze the contact and account timeline and persist one human-reviewable outreach suggestion."
  end

  def execute(_conn, %{"contact_id" => contact_id}) do
    case Outreach.generate_recommendation(contact_id) do
      {:ok, recommendation} -> {:ok, OutreachSerializer.recommendation_response(recommendation)}
      {:error, :not_found} -> {:error, "Outreach contact not found: #{contact_id}"}
      {:error, reason} -> {:error, "Could not generate an outreach next step: #{inspect(reason)}"}
    end
  end
end
