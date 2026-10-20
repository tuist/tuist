defmodule Atlas.MCP.Tools.DismissOutreachNextStep do
  @moduledoc "Dismisses an outreach suggestion and preserves feedback for the agent."

  use Atlas.MCP.Tool,
    name: "dismiss_outreach_next_step",
    schema: %{
      "type" => "object",
      "required" => ["recommendation_id", "reason"],
      "properties" => %{
        "recommendation_id" => %{"type" => "string"},
        "reason" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.recommendation_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description, do: "Dismiss a suggestion and save the reason so later recommendations can improve."

  def execute(conn, %{"recommendation_id" => id, "reason" => reason}) do
    case Outreach.dismiss_recommendation(id, reason, Tool.current_user(conn)) do
      {:ok, recommendation} -> {:ok, OutreachSerializer.recommendation_response(recommendation)}
      {:error, :not_found} -> {:error, "Outreach recommendation not found: #{id}"}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      {:error, error} -> {:error, "Could not dismiss the outreach next step: #{inspect(error)}"}
    end
  end
end
