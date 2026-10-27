defmodule Atlas.MCP.Tools.EnrollOutreachCandidate do
  @moduledoc """
  Promotes an Atlas-owned candidate into an account contact and outreach queue.
  """

  use Atlas.MCP.Tool,
    name: "enroll_outreach_candidate",
    schema: %{
      "type" => "object",
      "required" => ["candidate_id"],
      "properties" => %{"candidate_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Outreach.full_contact_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do: "Add an Atlas-owned Apollo search candidate to LinkedIn outreach, creating its prospect account when needed."

  def execute(conn, %{"candidate_id" => id}) do
    case Outreach.enroll_candidate(id, Tool.current_user(conn)) do
      {:ok, contact} ->
        {:ok, OutreachSerializer.full_contact(contact)}

      {:error, :not_found} ->
        {:error, "Outreach candidate not found: #{id}"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not add candidate: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not add candidate: #{inspect(reason)}"}
    end
  end
end
