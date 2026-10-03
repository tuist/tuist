defmodule Atlas.MCP.Tools.RejectAccountOutcomeProposal do
  @moduledoc "Rejects a pending outcome proposal with feedback."

  use Atlas.MCP.Tool,
    name: "reject_account_outcome_proposal",
    schema: %{
      "type" => "object",
      "required" => ["proposal_id", "reason"],
      "properties" => %{
        "proposal_id" => %{"type" => "string"},
        "reason" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.outcome_proposal_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Reject a suggestion and preserve feedback for future proposal runs."

  def execute(conn, %{"proposal_id" => id, "reason" => reason}) do
    case Accounts.get_outcome_proposal(id) do
      nil ->
        {:error, "Outcome proposal not found: #{id}"}

      proposal ->
        case Accounts.reject_outcome_proposal(proposal, reason, Tool.current_user(conn)) do
          {:ok, rejected} ->
            {:ok, AccountSerializer.outcome_proposal(Accounts.get_outcome_proposal(rejected.id))}

          {:error, changeset} ->
            {:error, Tool.format_changeset_errors(changeset)}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "proposal_id and reason are required."}
end
