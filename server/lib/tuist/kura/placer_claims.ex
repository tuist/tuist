defmodule Tuist.Kura.PlacerClaims do
  @moduledoc """
  The claims automatic sizing chose, and the resolution around them: an
  account's instances are built at the sized claim when it has one and its
  plan's constant otherwise.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.PlacerClaim
  alias Tuist.Kura.Regions
  alias Tuist.Repo

  @doc """
  The claim an account's storage-governed instances are built at.
  """
  def effective_claim_size(%Account{} = account) do
    claim_for(account) || plan_claim_size(account)
  end

  @doc """
  The claim the account's plan starts it at, which sizing then moves.
  """
  def plan_claim_size(%Account{} = account) do
    %{claim_size: claim_size} = Regions.storage_profile(AccountPolicies.sizing_plan(account))

    claim_size
  end

  @doc """
  The claim sizing chose for the account, or `nil` when it never sized it.
  """
  def claim_for(%Account{id: account_id}) do
    case Repo.get_by(PlacerClaim, account_id: account_id) do
      nil -> nil
      %PlacerClaim{claim_size: claim_size} -> claim_size
    end
  end

  @doc """
  Writes `claim_size` as the account's sized claim. Runs inside the caller's
  transaction; reaching running instances is the caller's job, exactly like
  the operator override path.
  """
  def put(%Account{id: account_id}, claim_size) when is_binary(claim_size) do
    %PlacerClaim{}
    |> PlacerClaim.changeset(%{account_id: account_id, claim_size: claim_size})
    |> Repo.insert(
      on_conflict: {:replace, [:claim_size, :updated_at]},
      conflict_target: :account_id
    )
    |> case do
      {:ok, _claim} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end
end
