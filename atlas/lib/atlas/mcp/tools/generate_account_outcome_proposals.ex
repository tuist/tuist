defmodule Atlas.MCP.Tools.GenerateAccountOutcomeProposals do
  @moduledoc "Generates evidence-based outcome proposals for human review."

  use Atlas.MCP.Tool,
    name: "generate_account_outcome_proposals",
    schema: %{
      "type" => "object",
      "properties" => Atlas.MCP.AccountLookup.identifier_schema_properties()
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
  def description do
    "Analyze account evidence and create suggestions that require human approval before changing outcomes."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args),
         {:ok, proposals} <- Accounts.generate_outcome_proposals(account.id) do
      proposals = Enum.map(proposals, &AccountSerializer.outcome_proposal/1)
      {:ok, AccountSerializer.list_response(:proposals, proposals)}
    else
      {:error, reason} -> {:error, "Could not generate outcome proposals: #{inspect(reason)}"}
    end
  end
end
