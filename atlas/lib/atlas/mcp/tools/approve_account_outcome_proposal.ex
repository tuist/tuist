defmodule Atlas.MCP.Tools.ApproveAccountOutcomeProposal do
  @moduledoc "Approves and applies a pending outcome proposal."

  use Atlas.MCP.Tool,
    name: "approve_account_outcome_proposal",
    schema: %{
      "type" => "object",
      "required" => ["proposal_id"],
      "properties" => %{"proposal_id" => %{"type" => "string"}}
    },
    output_schema: Atlas.MCP.Serializers.Accounts.outcome_proposal_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Approve a reviewed suggestion and create its outcome or outcome review."

  def execute(conn, %{"proposal_id" => id}) do
    case Accounts.get_outcome_proposal(id) do
      nil ->
        {:error, "Outcome proposal not found: #{id}"}

      proposal ->
        case Accounts.approve_outcome_proposal(proposal, Tool.current_user(conn)) do
          {:ok, %{proposal: approved}} ->
            {:ok, AccountSerializer.outcome_proposal(Accounts.get_outcome_proposal(approved.id))}

          {:error, reason} ->
            {:error, "Could not approve outcome proposal: #{inspect(reason)}"}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "proposal_id is required."}
end
