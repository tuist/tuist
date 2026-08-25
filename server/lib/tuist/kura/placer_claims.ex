defmodule Tuist.Kura.PlacerClaims do
  @moduledoc """
  Reads and writes the claims automatic sizing chose. Sits below the operator
  override in `Tuist.Kura.StorageClaims.effective_claim_size/1` and above the
  plan constant; an account with an operator override is invisible to sizing,
  so a row here only ever takes effect for unoverridden accounts.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Kura.PlacerClaim
  alias Tuist.Repo

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
