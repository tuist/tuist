defmodule Atlas.MCP.Tools.GenerateOutreachNextStep do
  @moduledoc "Generates one evidence-based guided next step for an outreach contact."

  use Atlas.MCP.Tool,
    name: "generate_outreach_next_step",
    schema: %{
      "type" => "object",
      "required" => ["contact_id"],
      "properties" => %{
        "contact_id" => %{"type" => "string"},
        "sender_email" => %{
          "type" => "string",
          "description" =>
            "Atlas email of the teammate who will send it from their own account. Defaults to the caller."
        },
        "channel" => %{"type" => "string", "enum" => Atlas.Outreach.MessageAttempt.channels()}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.recommendation_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description do
    "Analyze the contact and account timeline and persist one human-reviewable outreach suggestion, drafted in the voice of the teammate who will send it from their own LinkedIn or X account. Atlas never sends it; the teammate sends it themselves and then calls complete_outreach_next_step."
  end

  def execute(conn, %{"contact_id" => contact_id} = args) do
    with {:ok, sender} <- sender(conn, args["sender_email"]) do
      result = Outreach.generate_recommendation(contact_id, sender_id: sender && sender.id, channel: args["channel"])
      respond(result, contact_id)
    end
  end

  defp sender(conn, nil), do: {:ok, Tool.current_user(conn)}

  defp sender(_conn, email) do
    case Atlas.Users.get_user_by_email(email) do
      nil -> {:error, "No Atlas user has the email #{email}."}
      user -> {:ok, user}
    end
  end

  defp respond(result, contact_id) do
    case result do
      {:ok, recommendation} -> {:ok, OutreachSerializer.recommendation_response(recommendation)}
      {:error, :not_found} -> {:error, "Outreach contact not found: #{contact_id}"}
      {:error, reason} -> {:error, "Could not generate an outreach next step: #{inspect(reason)}"}
    end
  end
end
