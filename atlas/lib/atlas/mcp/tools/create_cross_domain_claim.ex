defmodule Atlas.MCP.Tools.CreateCrossDomainClaim do
  use Atlas.MCP.Tool,
    name: "create_cross_domain_claim",
    schema: %{
      "type" => "object",
      "required" => ["account_id", "claim_kind", "domains", "statement", "confidence", "sensitivity", "evidence"],
      "properties" => %{
        "account_id" => %{"type" => "string"},
        "claim_kind" => %{
          "type" => "string",
          "enum" => ["account_engagement_gap", "account_delivery_dependency", "account_renewal_exposure"]
        },
        "domains" => %{
          "type" => "array",
          "minItems" => 2,
          "items" => %{"type" => "string", "enum" => ["finance", "accounts", "outreach", "product"]}
        },
        "statement" => %{"type" => "string"},
        "confidence" => %{"type" => "number", "minimum" => 0.8, "maximum" => 1},
        "sensitivity" => %{"type" => "string", "enum" => ["public", "internal", "restricted"]},
        "link_basis" => %{
          "type" => "string",
          "description" => "Required for a human-verified account-to-product dependency."
        },
        "evidence" => %{
          "type" => "array",
          "minItems" => 2,
          "items" => %{
            "type" => "object",
            "required" => ["record_type", "record_id", "source_class", "observation"],
            "properties" => %{
              "record_type" => %{
                "type" => "string",
                "enum" => [
                  "account_event",
                  "account_term",
                  "account_outcome",
                  "account_outcome_review",
                  "outreach_message_attempt",
                  "product_trace",
                  "document"
                ]
              },
              "record_id" => %{"type" => "string"},
              "source_class" => %{
                "type" => "string",
                "enum" => ["observed", "human_asserted", "decided", "action_result"]
              },
              "observation" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      },
      "additionalProperties" => false
    },
    output_schema: Atlas.MCP.Serializers.Briefs.claim_schema()

  alias Atlas.Accounts
  alias Atlas.Coordination.Claims
  alias Atlas.MCP.Serializers.Briefs, as: BriefSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Create or supersede a high-confidence cross-domain claim. Heuristic links and finance vendor records are rejected."
  end

  def execute(conn, %{"account_id" => account_id} = args) do
    with :ok <- Tool.authorize_executive(conn, "Cross-domain claim tools"),
         account when not is_nil(account) <- Accounts.get_account(account_id),
         {:ok, claim} <-
           Claims.create(
             account,
             %{
               claim_kind: args["claim_kind"],
               domains: args["domains"],
               statement: args["statement"],
               confidence: args["confidence"],
               sensitivity: args["sensitivity"],
               link_basis: args["link_basis"],
               generated_by_agent: "mcp_agent"
             },
             args["evidence"],
             actor: Tool.current_user(conn),
             interface: "mcp"
           ) do
      {:ok, BriefSerializer.claim(Claims.get(claim.id))}
    else
      nil -> {:error, "Account not found: #{account_id}"}
      {:error, reason} -> {:error, "Cross-domain claim rejected: #{inspect(reason)}"}
    end
  end

  def execute(_conn, _args), do: {:error, "account_id is required."}
end
