defmodule Tuist.Kura.PlacerClaims do
  @moduledoc """
  The claims automatic sizing chose, and the resolution around them: an
  account's claim is what its governed instances are pinned at, then the sized
  claim, then its plan's constant.
  """

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.PlacerClaim
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  @doc """
  The account's claim: what a new instance in a storage-governed region is built
  at, and what claim sizing measures the account against.

  The largest claim pinned on the account's governed instances that still hold
  volumes comes first, then the sized claim, then the plan's. The claim is
  account-wide: Kura replicates the account's content into every instance, so
  one built smaller evicts that content sooner than the rest, and sizing, which
  grows the whole account when any instance runs short, reads it as a reason to
  grow all of them. Pins lead the sized claim because they can exist without
  one, and lead the plan because they outlive a change to its constants.
  """
  def effective_claim_size(%Account{id: account_id} = account) do
    resolve_claim_size(account, Map.get(pinned_claims([account_id]), account_id), claim_for(account))
  end

  @doc """
  `effective_claim_size/1` over a pin and a sized claim the caller already read,
  for a pass that reads them for many accounts at once.
  """
  def resolve_claim_size(%Account{} = account, pinned, sized) do
    pinned || sized || plan_claim_size(account)
  end

  @doc """
  The largest claim each account's governed instances are pinned at, by account
  id. Instances in a volumeless status hold no claim and are skipped, and an
  account with no pin is absent.

  Largest, because a baseline under what an instance holds turns a proposed
  grow into a silent shrink of that instance's volume.
  """
  def pinned_claims(account_ids) do
    Server
    |> where([server], server.account_id in ^account_ids)
    |> where([server], server.region in ^governed_region_ids())
    |> where([server], server.status not in ^Tuist.Kura.volumeless_statuses())
    |> where([server], not is_nil(server.storage_claim_size))
    |> select([server], {server.account_id, server.storage_claim_size})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {account_id, claims} -> {account_id, largest_claim(claims)} end)
    |> Map.reject(fn {_account_id, claim} -> is_nil(claim) end)
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

  defp largest_claim(claims) do
    claims
    |> Enum.flat_map(fn claim ->
      case Regions.parse_storage_quantity(claim) do
        {:ok, bytes} -> [{claim, bytes}]
        :error -> []
      end
    end)
    |> case do
      [] -> nil
      parsed -> parsed |> Enum.max_by(&elem(&1, 1)) |> elem(0)
    end
  end

  # Region configuration, not runtime availability: an instance in a governed
  # region holds its account's claim wherever the control plane runs.
  defp governed_region_ids do
    Regions.all()
    |> Enum.filter(&Regions.storage_governed?/1)
    |> Enum.map(& &1.id)
  end
end
