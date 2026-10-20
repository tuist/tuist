defmodule Atlas.MCP.Tools.ListAccountOutcomeProposals do
  @moduledoc "Lists outcome proposals awaiting review for an account."

  use Atlas.MCP.Tool,
    name: "list_account_outcome_proposals",
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Atlas.MCP.AccountLookup.identifier_schema_properties(), "status", %{
          "type" => "string",
          "enum" => ["pending", "approved", "rejected"]
        })
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.list_response_schema(
        :proposals,
        Atlas.MCP.Serializers.Accounts.outcome_proposal_schema()
      )

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer

  @impl EMCP.Tool
  def description, do: "List evidence, confidence, rationale, and review status for account outcome proposals."

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      statuses = if is_binary(args["status"]), do: [args["status"]], else: ["pending"]

      proposals =
        account
        |> Accounts.list_outcome_proposals(statuses: statuses)
        |> Enum.map(&AccountSerializer.outcome_proposal/1)

      {:ok, AccountSerializer.list_response(:proposals, proposals)}
    end
  end
end
