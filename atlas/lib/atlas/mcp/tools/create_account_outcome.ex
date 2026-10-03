defmodule Atlas.MCP.Tools.CreateAccountOutcome do
  @moduledoc "Creates a measurable customer outcome for an account."

  use Atlas.MCP.Tool,
    name: "create_account_outcome",
    schema: %{
      "type" => "object",
      "required" => ["title", "motion"],
      "properties" =>
        Map.merge(Atlas.MCP.AccountLookup.identifier_schema_properties(), %{
          "title" => %{"type" => "string"},
          "motion" => %{
            "type" => "string",
            "enum" => ["evaluation", "adoption", "expansion", "renewal", "recovery"]
          },
          "description" => %{"type" => "string"},
          "success_measure" => %{"type" => "string"},
          "baseline" => %{"type" => "string"},
          "target" => %{"type" => "string"},
          "target_date" => %{"type" => "string", "format" => "date"}
        })
    },
    output_schema: Atlas.MCP.Serializers.Accounts.outcome_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Create a measurable customer outcome after explicit user authorization. Use generate_account_outcome_proposals for inferred suggestions."
  end

  def execute(conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      attrs =
        Map.take(args, [
          "title",
          "motion",
          "description",
          "success_measure",
          "baseline",
          "target",
          "target_date"
        ])

      case Accounts.create_outcome(account, attrs, Tool.current_user(conn)) do
        {:ok, outcome} -> {:ok, AccountSerializer.outcome(Accounts.get_outcome(outcome.id))}
        {:error, changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      end
    end
  end
end
