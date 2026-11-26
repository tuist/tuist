defmodule Atlas.MCP.Tools.RecordOutreachEventV2 do
  @moduledoc """
  Records a LinkedIn or X connection, message, or internal note for a contact.
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
          "description" =>
            "Classification to use when kind is message_received. Use meeting_booked when the conversation led to a meeting."
        },
        "occurred_at" => %{"type" => "string", "format" => "date-time"},
        "channel" => %{"type" => "string", "enum" => Atlas.Outreach.MessageAttempt.channels()},
        "sender_email" => %{
          "type" => "string",
          "description" => "Atlas email of the teammate whose own account sent it. Defaults to the caller."
        }
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.full_contact_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do:
      "Record a connection request, accepted connection, sent or received message (on LinkedIn or X), booked meeting, or internal note in a contact's outreach history, with the teammate who sent it."

  def execute(conn, %{"contact_id" => id} = args) do
    attrs = Map.take(args, ["kind", "subject", "body", "response_outcome", "occurred_at", "channel"])

    with {:ok, attrs} <- put_sender(attrs, args["sender_email"]) do
      record(id, attrs, Tool.current_user(conn))
    end
  end

  defp put_sender(attrs, nil), do: {:ok, attrs}

  defp put_sender(attrs, email) do
    case Atlas.Users.get_user_by_email(email) do
      nil -> {:error, "No Atlas user has the email #{email}."}
      user -> {:ok, Map.put(attrs, "sender_id", user.id)}
    end
  end

  defp record(id, attrs, actor) do
    case Outreach.record_event(id, attrs, actor) do
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
