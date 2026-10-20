defmodule Atlas.MCP.Tools.ListOutreachCandidates do
  @moduledoc """
  Lists Apollo search candidates owned by Atlas.
  """

  use Atlas.MCP.Tool,
    name: "list_outreach_candidates",
    schema: %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => Atlas.Outreach.Candidate.statuses()},
        "search_segment" => %{
          "type" => "string",
          "enum" => ["mobile_mid_large", "mobile_giants"]
        },
        "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 100}
      }
    },
    output_schema: Atlas.MCP.Serializers.Outreach.candidate_list_response_schema()

  alias Atlas.MCP.Serializers.Outreach, as: OutreachSerializer
  alias Atlas.Outreach

  @impl EMCP.Tool
  def description,
    do: "List Apollo-discovered candidates kept in Atlas, optionally filtered by review status, search, or segment."

  def execute(_conn, args) do
    {candidates, _meta} =
      Outreach.list_candidates(
        query: args["query"],
        status: args["status"] || "pending",
        search_segment: args["search_segment"],
        limit: args["limit"] || 25
      )

    {:ok, OutreachSerializer.candidate_list_response(candidates)}
  end
end
