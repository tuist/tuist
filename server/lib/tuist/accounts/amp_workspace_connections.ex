defmodule Tuist.Accounts.AmpWorkspaceConnections do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AmpWorkspaceConnection
  alias Tuist.Repo

  def list(%Account{id: account_id}) do
    Repo.all(from c in AmpWorkspaceConnection, where: c.account_id == ^account_id, order_by: c.id)
  end

  # Callers must have verified an Amp identity token from `workspace_id`
  # before connecting it; the workspace ID alone proves nothing.
  def create(%Account{id: account_id}, workspace_id) do
    %AmpWorkspaceConnection{account_id: account_id}
    |> AmpWorkspaceConnection.changeset(%{workspace_id: workspace_id})
    |> Repo.insert()
  end

  def delete(%Account{id: account_id}, connection_id) do
    case Repo.get_by(AmpWorkspaceConnection, id: connection_id, account_id: account_id) do
      nil -> {:error, :not_found}
      connection -> Repo.delete(connection)
    end
  end

  @doc """
  The account a verified Amp workspace exchanges into. Without an account
  handle, the workspace must be connected to exactly one account.
  """
  def account_for_workspace(workspace_id, account_handle) do
    query =
      from connection in AmpWorkspaceConnection,
        join: account in assoc(connection, :account),
        where: connection.workspace_id == ^workspace_id,
        select: account

    query = if account_handle in [nil, ""], do: query, else: where(query, [_, account], account.name == ^account_handle)

    case Repo.all(query) do
      [] -> {:error, :amp_workspace_not_connected}
      [account] -> {:ok, account}
      accounts -> {:error, :ambiguous_amp_workspace, accounts |> Enum.map(& &1.name) |> Enum.sort()}
    end
  end
end
