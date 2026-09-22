defmodule Atlas.MCP.AccountLookup do
  @moduledoc """
  Resolves an account from either an `account_id` (UUID), `account_key`,
  or `handle` argument. Used by every account-scoped MCP tool so callers
  can reference accounts however they prefer.
  """

  import Ecto.Query

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.AccountHandle
  alias Atlas.Repo

  def resolve(%{"account_id" => id}) when is_binary(id) and id != "" do
    case Repo.get(Account, id) do
      nil -> {:error, "Account not found for account_id: #{id}"}
      account -> {:ok, account}
    end
  end

  def resolve(%{"account_key" => key}) when is_binary(key) and key != "" do
    case Repo.get_by(Account, account_key: key) do
      nil -> {:error, "Account not found for account_key: #{key}"}
      account -> {:ok, account}
    end
  end

  def resolve(%{"handle" => handle}) when is_binary(handle) and handle != "" do
    account =
      Account
      |> join(:inner, [account], handle in AccountHandle, on: handle.account_id == account.id)
      |> where([_account, handle], handle.handle == ^handle)
      |> limit(1)
      |> Repo.one()

    case account do
      nil -> {:error, "Account not found for handle: #{handle}"}
      account -> {:ok, account}
    end
  end

  def resolve(_), do: {:error, "Provide one of account_id, account_key, or handle."}

  def identifier_schema_properties do
    %{
      "account_id" => %{
        "type" => "string",
        "description" => "UUID of the account."
      },
      "account_key" => %{
        "type" => "string",
        "description" => "External account_key (e.g. \"acme-co\")."
      },
      "handle" => %{
        "type" => "string",
        "description" => "An account_handle (e.g. a Slack channel, domain, or alias)."
      }
    }
  end
end
