defmodule Atlas.MCP.Tools.UpdateAccountTerm do
  @moduledoc """
  Updates fields on an existing contract term.
  """

  use Atlas.MCP.Tool,
    name: "update_account_term",
    schema: %{
      "type" => "object",
      "required" => ["term_id"],
      "properties" =>
        Map.merge(
          %{"term_id" => %{"type" => "string", "description" => "UUID of the term to update."}},
          Atlas.MCP.TermFields.schema_properties()
        )
    },
    output_schema: Atlas.MCP.Serializers.Accounts.term_schema()

  alias Atlas.Accounts
  alias Atlas.Accounts.Term
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.TermFields
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "Update fields on an existing contract term (dates, seats, pricing, deployment, PO)."

  def execute(_conn, %{"term_id" => id} = args) when is_binary(id) do
    case Repo.get(Term, id) do
      nil ->
        {:error, "Term not found: #{id}"}

      term ->
        attrs = Map.take(args, TermFields.keys())

        case Accounts.update_term(term, attrs) do
          {:ok, updated} ->
            {:ok, AccountSerializer.term(updated)}

          {:error, changeset} ->
            {:error, "Could not update term: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "term_id is required."}
end
