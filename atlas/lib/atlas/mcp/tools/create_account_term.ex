defmodule Atlas.MCP.Tools.CreateAccountTerm do
  @moduledoc """
  Adds a contract term to an account.
  """

  use Atlas.MCP.Tool,
    name: "create_account_term",
    schema: %{
      "type" => "object",
      "required" => ["payment", "start_date", "total"],
      "description" =>
        "Provide one of account_id, account_key, or handle. To renew a contract, list the account's terms, copy the most recent one, and shift start_date/end_date forward.",
      "properties" =>
        Map.merge(
          Atlas.MCP.AccountLookup.identifier_schema_properties(),
          Atlas.MCP.TermFields.schema_properties()
        )
    },
    output_schema: Atlas.MCP.Serializers.Accounts.term_schema()

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.TermFields
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description do
    "Add a contract term to an account (dates, seats, pricing, deployment, PO). To renew, copy the account's most recent term (see list_account_terms) and shift the dates."
  end

  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      attrs = Map.take(args, TermFields.keys())

      case Accounts.create_term(account, attrs) do
        {:ok, term} -> {:ok, AccountSerializer.term(term)}
        {:error, changeset} -> {:error, "Could not create term: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
