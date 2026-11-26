defmodule Atlas.MCP.Tools.ListOutreachContacts do
  @moduledoc """
  Lists contacts enrolled in LinkedIn outreach.
  """

  use Atlas.MCP.Tool,
    name: "list_outreach_contacts",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string"},
        # Frozen as gtm.outreach.contacts.list@1; get_outreach_results reports booked meetings.
        "status" => %{
          "type" => "string",
          "enum" =>
            ~w(not_contacted connection_requested connected conversation_started replied interested not_interested)
        },
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.list_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do: "List account contacts enrolled in LinkedIn outreach, optionally filtered by stage or search text."

  def execute(_conn, args) do
    {contacts, _meta} =
      Outreach.list_contacts(
        query: args["query"],
        status: args["status"],
        limit: args["limit"] || 25
      )

    {:ok, OutreachSerializer.list_response(contacts)}
  end
end
