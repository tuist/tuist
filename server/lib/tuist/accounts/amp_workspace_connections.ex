defmodule Tuist.Accounts.AmpWorkspaceConnections do
  @moduledoc false

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.AmpWorkspaceConnection
  alias Tuist.Repo

  def list(%Account{id: account_id}) do
    Repo.all(from c in AmpWorkspaceConnection, where: c.account_id == ^account_id, order_by: c.id)
  end

  def create(%Account{id: account_id}, attrs) do
    %AmpWorkspaceConnection{account_id: account_id}
    |> AmpWorkspaceConnection.changeset(attrs)
    |> Repo.insert()
  end

  def delete(%Account{id: account_id}, connection_id) do
    case Repo.get_by(AmpWorkspaceConnection, id: connection_id, account_id: account_id) do
      nil -> {:error, :not_found}
      connection -> Repo.delete(connection)
    end
  end

  @doc """
  The account a verified Amp orb exchanges into. A connection matches the
  orb's workspace and, when it names one, the orb's Amp project. Without an
  account handle, exactly one account must match.
  """
  def account_for_workspace(workspace_id, project_id, account_handle) do
    query =
      from connection in AmpWorkspaceConnection,
        join: account in assoc(connection, :account),
        where: connection.workspace_id == ^workspace_id,
        select: account

    query =
      if project_id,
        do: where(query, [c], is_nil(c.project_id) or c.project_id == ^project_id),
        else: where(query, [c], is_nil(c.project_id))

    query = if account_handle in [nil, ""], do: query, else: where(query, [_, account], account.name == ^account_handle)

    case Repo.all(query) do
      [] -> {:error, :amp_workspace_not_connected}
      [account] -> {:ok, account}
      accounts -> {:error, :ambiguous_amp_workspace, accounts |> Enum.map(& &1.name) |> Enum.sort()}
    end
  end
end
