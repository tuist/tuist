defmodule Atlas.MCP.Tools.ListCrossDomainClaims do
  use Atlas.MCP.Tool,
    name: "list_cross_domain_claims",
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_id" => %{"type" => "string"},
        "claim_kind" => %{
          "type" => "string",
          "enum" => ["account_engagement_gap", "account_delivery_dependency", "account_renewal_exposure"]
        }
      }
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "claims" => %{"type" => "array", "items" => Atlas.MCP.Serializers.Briefs.claim_schema()},
        "count" => %{"type" => "integer"}
      },
      "required" => ["claims", "count"],
      "additionalProperties" => false
    }

  alias Atlas.Coordination.Claims
  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "List current, versioned claims supported by evidence from at least two domains."

  def execute(conn, args) do
    with :ok <- Tool.authorize_scope(conn, "engineering:read", "Cross-domain claim tools") do
      claims = Claims.list_current(account_id: args["account_id"], claim_kind: args["claim_kind"])
      {:ok, %{claims: Enum.map(claims, &BriefSerializer.claim/1), count: length(claims)}}
    end
  end
end
