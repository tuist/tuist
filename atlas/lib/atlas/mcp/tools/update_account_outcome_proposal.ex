defmodule Atlas.MCP.Tools.UpdateAccountOutcomeProposal do
  @moduledoc "Edits a pending outcome proposal before approval."

  use Atlas.MCP.Tool,
    name: "update_account_outcome_proposal",
    schema: %{
      "type" => "object",
      "required" => ["proposal_id"],
      "properties" => %{
        "proposal_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "motion" => %{
          "type" => "string",
          "enum" => ["evaluation", "adoption", "expansion", "renewal", "recovery"]
        },
        "success_measure" => %{"type" => "string"},
        "baseline" => %{"type" => "string"},
        "target" => %{"type" => "string"},
        "target_date" => %{"type" => "string", "format" => "date"},
        "health" => %{"type" => "string", "enum" => ["unknown", "on_track", "at_risk", "off_track"]},
        "summary" => %{"type" => "string"},
        "recommendation" => %{"type" => "string"},
        "rationale" => %{"type" => "string"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.outcome_proposal_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Edit a pending outcome or review suggestion without applying it."

  def execute(conn, %{"proposal_id" => id} = args) do
    case Accounts.get_outcome_proposal(id) do
      nil ->
        {:error, "Outcome proposal not found: #{id}"}

      proposal ->
        attrs =
          Map.take(args, [
            "title",
            "description",
            "motion",
            "success_measure",
            "baseline",
            "target",
            "target_date",
            "health",
            "summary",
            "recommendation",
            "rationale"
          ])

        case Accounts.update_outcome_proposal(proposal, attrs, Tool.current_user(conn)) do
          {:ok, updated} -> {:ok, AccountSerializer.outcome_proposal(Accounts.get_outcome_proposal(updated.id))}
          {:error, changeset} -> {:error, Tool.format_changeset_errors(changeset)}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "proposal_id is required."}
end
