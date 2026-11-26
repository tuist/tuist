defmodule Atlas.MCP.Tools.RecordOutreachEvent do
  @moduledoc """
  Frozen `gtm.outreach.events.record@1` adapter for published automation workflows.
  The MCP server registers `RecordOutreachEventV2`, which also accepts a channel, a sender and booked meetings.
  """

  use Atlas.MCP.Tool,
    name: "record_outreach_event",
    schema: %{
      "type" => "object",
      "required" => ["contact_id", "kind"],
      "properties" => %{
        "contact_id" => %{"type" => "string"},
        "kind" => %{
          "type" => "string",
          "enum" => ["connection_requested", "connection_accepted", "message_sent", "message_received", "note"]
        },
        "subject" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" => "The visible subject when recording an InMail message."
        },
        "body" => %{"type" => "string"},
        "response_outcome" => %{
          "type" => "string",
          "enum" => ["replied", "positive_reply", "objection", "not_interested"],
          "description" => "Classification to use when kind is message_received."
        },
        "occurred_at" => %{"type" => "string", "format" => "date-time"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.full_contact_schema()

  alias Atlas.MCP.Tools.RecordOutreachEventV2

  @impl EMCP.Tool
  def description,
    do:
      "Record a connection request, accepted connection, sent or received message, or internal note in a contact's outreach history."

  def execute(conn, args), do: RecordOutreachEventV2.execute(conn, args)
end
