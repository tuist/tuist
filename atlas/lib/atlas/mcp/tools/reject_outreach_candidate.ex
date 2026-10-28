defmodule Atlas.MCP.Tools.RejectOutreachCandidate do
  @moduledoc """
  Rejects an Atlas-owned outreach candidate.
  """

  use Atlas.MCP.Tool,
    name: "reject_outreach_candidate",
    schema: %{
      "type" => "object",
      "required" => ["candidate_id"],
      "properties" => %{
        "candidate_id" => %{"type" => "string"},
        "reason" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.candidate_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description, do: "Dismiss an Atlas-owned outreach candidate and optionally record why."

  def execute(conn, %{"candidate_id" => id} = args) do
    case Outreach.reject_candidate(id, args["reason"], Tool.current_user(conn)) do
      {:ok, candidate} ->
        {:ok, OutreachSerializer.candidate(candidate)}

      {:error, :not_found} ->
        {:error, "Outreach candidate not found: #{id}"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, "Could not dismiss candidate: #{Tool.format_changeset_errors(changeset)}"}

      {:error, reason} ->
        {:error, "Could not dismiss candidate: #{inspect(reason)}"}
    end
  end
end
