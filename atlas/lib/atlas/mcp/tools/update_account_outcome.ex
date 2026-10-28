defmodule Atlas.MCP.Tools.UpdateAccountOutcome do
  @moduledoc "Updates an account outcome."

  use Atlas.MCP.Tool,
    name: "update_account_outcome",
    schema: %{
      "type" => "object",
      "required" => ["outcome_id"],
      "properties" => %{
        "outcome_id" => %{"type" => "string"},
        "title" => %{"type" => "string"},
        "description" => %{"type" => "string"},
        "status" => %{"type" => "string", "enum" => ["active", "achieved", "missed", "abandoned"]},
        "motion" => %{
          "type" => "string",
          "enum" => ["evaluation", "adoption", "expansion", "renewal", "recovery"]
        },
        "success_measure" => %{"type" => "string"},
        "baseline" => %{"type" => "string"},
        "target" => %{"type" => "string"},
        "target_date" => %{"type" => "string", "format" => "date"}
      }
    },
    output_schema: Atlas.MCP.Serializers.Accounts.outcome_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description, do: "Update the definition or lifecycle status of a customer outcome."

  def execute(_conn, %{"outcome_id" => id} = args) do
    case Accounts.get_outcome(id) do
      nil ->
        {:error, "Outcome not found: #{id}"}

      outcome ->
        attrs =
          Map.take(args, [
            "title",
            "description",
            "status",
            "motion",
            "success_measure",
            "baseline",
            "target",
            "target_date"
          ])

        case Accounts.update_outcome(outcome, attrs) do
          {:ok, updated} -> {:ok, AccountSerializer.outcome(Accounts.get_outcome(updated.id))}
          {:error, changeset} -> {:error, Tool.format_changeset_errors(changeset)}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "outcome_id is required."}
end
