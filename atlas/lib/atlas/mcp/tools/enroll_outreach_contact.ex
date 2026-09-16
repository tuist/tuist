defmodule Atlas.MCP.Tools.EnrollOutreachContact do
  @moduledoc """
  Promotes an Apollo suggestion into an account contact and outreach queue.
  """

  use Atlas.MCP.Tool,
    name: "enroll_outreach_contact",
    schema: %{
      "type" => "object",
      "required" => ["opportunity_contact_id"],
      "properties" => %{"opportunity_contact_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Outreach.full_contact_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do:
      "Add an Apollo or public-signal contact suggestion to LinkedIn outreach, creating its prospect account when needed."

  def execute(conn, %{"opportunity_contact_id" => id}) do
    case Outreach.enroll_opportunity_contact(id, Tool.current_user(conn)) do
      {:ok, contact} ->
        {:ok, OutreachSerializer.full_contact(contact)}

      {:error, :not_found} ->
        {:error, "Opportunity contact not found: #{id}"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not add contact: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not add contact: #{inspect(reason)}"}
    end
  end
end
