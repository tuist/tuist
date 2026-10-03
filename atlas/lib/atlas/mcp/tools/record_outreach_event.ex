defmodule Atlas.MCP.Tools.RecordOutreachEvent do
  @moduledoc """
  Records a LinkedIn connection, message, or internal note for a contact.
  """

  use Atlas.MCP.Tool,
    name: "record_outreach_event",
    schema: %{
      "type" => "object",
      "required" => ["contact_id", "kind"],
      "properties" => %{
        "contact_id" => %{"type" => "string"},
        "kind" => %{"type" => "string", "enum" => Atlas.Outreach.event_kinds()},
        "subject" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" => "The visible subject when recording an InMail message."
        },
        "body" => %{"type" => "string"},
        "response_outcome" => %{
          "type" => "string",
          "enum" => Atlas.Outreach.response_outcomes(),
          "description" => "Classification to use when kind is message_received."
        },
        "occurred_at" => %{"type" => "string", "format" => "date-time"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.full_contact_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do:
      "Record a connection request, accepted connection, sent or received message, or internal note in a contact's outreach history."

  def execute(conn, %{"contact_id" => id} = args) do
    attrs = Map.take(args, ["kind", "subject", "body", "response_outcome", "occurred_at"])

    case Outreach.record_event(id, attrs, Tool.current_user(conn)) do
      {:ok, _event, contact} ->
        {:ok, OutreachSerializer.full_contact(contact)}

      {:error, :not_found} ->
        {:error, "Outreach contact not found: #{id}"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not record outreach event: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not record outreach event: #{inspect(reason)}"}
    end
  end
end
