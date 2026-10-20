defmodule Atlas.MCP.Tools.DeleteAccountTerm do
  @moduledoc """
  Deletes a contract term from an account.
  """

  use Atlas.MCP.Tool,
    name: "delete_account_term",
    schema: %{
      "type" => "object",
      "required" => ["term_id"],
      "properties" => %{
        "term_id" => %{"type" => "string", "description" => "UUID of the term to delete."}
      }
    },
    output_schema:
      Atlas.MCP.Serializers.Accounts.term_schema()
      |> Map.update!("properties", &Map.put(&1, "deleted", %{"type" => "boolean"}))
      |> Map.update!("required", &(&1 ++ ["deleted"]))

  alias Atlas.Accounts
  alias Atlas.Accounts.Term
  alias Atlas.MCP.Serializers.Accounts, as: AccountSerializer
  alias Atlas.MCP.Tool
  alias Atlas.Repo

  @impl EMCP.Tool
  def description, do: "Delete a contract term from an account."

  def execute(_conn, %{"term_id" => id}) when is_binary(id) do
    case Repo.get(Term, id) do
      nil ->
        {:error, "Term not found: #{id}"}

      term ->
        case Accounts.delete_term(term) do
          {:ok, deleted} ->
            {:ok, Map.put(AccountSerializer.term(deleted), :deleted, true)}

          {:error, changeset} ->
            {:error, "Could not delete term: #{Tool.format_changeset_errors(changeset)}"}
        end
    end
  end

  def execute(_conn, _args), do: {:error, "term_id is required."}
end
