defmodule Tuist.Sandboxes.AmpIntegrations do
  @moduledoc "Account-owned Amp connections. Credentials never leave the control plane and provider pod."
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpIntegration
  alias Tuist.Sandboxes.AmpReconciler

  def get(account_id), do: Repo.get_by(AmpIntegration, account_id: account_id)

  # Reload authorization on every mutation, including events from already-open pages.
  def connect(account_id, user, token) when is_binary(token) and byte_size(token) <= 4096 do
    mutate(account_id, user, fn account ->
      if FeatureFlags.sandboxes_enabled?(account) do
        (get(account.id) || %AmpIntegration{account_id: account.id})
        |> AmpIntegration.changeset(token)
        |> Repo.insert_or_update()
      else
        {:error, :disabled}
      end
    end)
  end

  def connect(_, _, _), do: {:error, :invalid_token}

  def disconnect(account_id, user) do
    mutate(account_id, user, fn account ->
      case get(account.id) do
        nil ->
          {:ok, nil}

        integration ->
          integration
          |> Ecto.Changeset.change(enabled: false, status: :disconnecting, provider_token: nil, token_fingerprint: nil)
          |> Repo.update()
      end
    end)
  end

  # Lifecycle writes must commit before commands reach the node: a transaction
  # spanning dispatch hides new rows from node reports and can roll back a VM's identity.
  def with_lock(account_id, fun) do
    Sandboxes.with_sandbox_lock("amp-integration:#{account_id}", fun, wait: false)
  end

  defp mutate(account_id, user, fun) do
    with_lock(account_id, fn -> mutate_locked(account_id, user, fun) end)
  end

  defp mutate_locked(account_id, user, fun) do
    Repo.transaction(fn ->
      account = Repo.one!(from a in Account, where: a.id == ^account_id, lock: "FOR UPDATE")

      with :ok <- Authorization.authorize(:account_update, user, account),
           {:ok, result} <- fun.(account),
           {:ok, _job} <- Oban.insert(AmpReconciler.new(%{"account_id" => account_id})) do
        result
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def public_status(nil), do: nil
  def public_status(integration), do: Map.take(integration, [:id, :enabled, :status, :updated_at, :last_checked_at])
end
