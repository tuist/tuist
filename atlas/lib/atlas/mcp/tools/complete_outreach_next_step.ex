defmodule Atlas.MCP.Tools.CompleteOutreachNextStep do
  @moduledoc "Marks an outreach next step complete and records it in the contact history."

  use Atlas.MCP.Tool,
    name: "complete_outreach_next_step",
    schema: %{
      "type" => "object",
      "required" => ["recommendation_id"],
      "properties" => %{
        "recommendation_id" => %{"type" => "string"},
        "sent_subject" => %{
          "type" => "string",
          "maxLength" => 120,
          "description" => "For InMail, the exact subject sent, including any edits to the suggested draft."
        },
        "sent_message" => %{
          "type" => "string",
          "description" => "The exact message sent, including any edits to the suggested draft."
        }
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.recommendation_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description do
    "After the user confirms the suggested action was performed, mark it complete and add the action to the outreach timeline."
  end

  def execute(conn, %{"recommendation_id" => id} = args) do
    attrs = Map.take(args, ["sent_subject", "sent_message"])

    case Outreach.complete_recommendation(id, Tool.current_user(conn), attrs) do
      {:ok, %{recommendation: recommendation}} ->
        {:ok, OutreachSerializer.recommendation_response(recommendation)}

      {:error, :not_found} ->
        {:error, "Outreach recommendation not found or no longer pending: #{id}"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Tool.format_changeset_errors(changeset)}

      {:error, reason} ->
        {:error, "Could not complete the outreach next step: #{inspect(reason)}"}
    end
  end
end
