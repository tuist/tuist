defmodule Atlas.MCP.Tools.MarkAccountNotAccount do
  @moduledoc """
  Marks an account row as not an account while preserving its identifiers as a
  blocklist for future automated ingestion.

  Consumers must provide exactly enough identifying data for
  `Atlas.MCP.AccountLookup.resolve/1` to find an account: `account_id`,
  `account_key`, or `handle`. An optional `reason` string is stored on the
  account for audit context.

  Successful calls return an `account` object with the account identifiers,
  name, and `not_an_account_*` fields so agents can confirm the suppression was
  applied without issuing a follow-up read.
  """

  use Atlas.MCP.Tool,
    name: "mark_account_not_account",
    schema: %{
      "type" => "object",
      "description" => "Provide one of account_id, account_key, or handle, plus an optional reason.",
      "properties" =>
        Map.put(Atlas.MCP.AccountLookup.identifier_schema_properties(), "reason", %{
          "type" => "string",
          "description" => "Short reason this row is not a customer, lead, or prospect account."
        })
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "account" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "account_key" => %{"type" => "string"},
            "name" => %{"type" => ["string", "null"]},
            "not_an_account_at" => %{"type" => ["string", "null"]},
            "not_an_account_reason" => %{"type" => ["string", "null"]}
          },
          "required" => ["id", "account_key", "name", "not_an_account_at", "not_an_account_reason"],
          "additionalProperties" => false
        }
      },
      "required" => ["account"],
      "additionalProperties" => false
    }

  alias Atlas.Accounts
  alias Atlas.MCP.AccountLookup
  alias Atlas.MCP.Tool

  @impl EMCP.Tool
  def description,
    do:
      "Mark an account as not an account. The row is hidden from account lists and blocks future agent-created accounts for the same identifiers."

  @doc """
  Resolves the target account from `args`, marks it as not an account, and
  returns the updated account identifier and suppression metadata.
  """
  def execute(_conn, args) do
    with {:ok, account} <- AccountLookup.resolve(args) do
      case Accounts.mark_account_not_account(account, Map.take(args, ["reason"])) do
        {:ok, updated} ->
          {:ok,
           %{
             account: %{
               id: updated.id,
               account_key: updated.account_key,
               name: updated.name,
               not_an_account_at: Tool.iso8601(updated.not_an_account_at),
               not_an_account_reason: updated.not_an_account_reason
             }
           }}

        {:error, changeset} ->
          {:error, "Could not mark account as not an account: #{Tool.format_changeset_errors(changeset)}"}
      end
    end
  end
end
