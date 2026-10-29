defmodule Atlas.MCP.Tools.GetOutreachContact do
  @moduledoc """
  Gets one outreach contact and its complete history.
  """

  use Atlas.MCP.Tool,
    name: "get_outreach_contact",
    schema: %{
      "type" => "object",
      "required" => ["contact_id"],
      "properties" => %{"contact_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Outreach.full_contact_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description, do: "Get an outreach contact with its linear connection and message history."

  def execute(_conn, %{"contact_id" => id}) do
    case Outreach.get_contact(id) do
      nil -> {:error, "Outreach contact not found: #{id}"}
      contact -> {:ok, OutreachSerializer.full_contact(contact)}
    end
  end
end
