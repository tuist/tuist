defmodule Tuist.Kura.ClaimProposals do
  @moduledoc """
  Runs the claim sizing sweep and keeps its proposal records.

  The sweep evaluates every account with live instances in storage-governed
  regions through `Tuist.Kura.ClaimSizing` and converges the proposal set:
  a fresh recommendation opens a proposal, a changed one supersedes the open
  one, a withdrawn one closes it. Acting on a proposal is not this module's
  job — `Tuist.Kura.apply_claim_proposal/2` is, whether an operator confirmed
  it or the automatic flag let the sweep call it directly.

  Accounts with an operator claim override are invisible to the sweep; the
  override is the per-account off switch for everything here.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.ClaimSizing
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageClaims
  alias Tuist.Kura.StorageRollups
  alias Tuist.Repo

  @doc """
  Evaluates every sizeable account and converges its proposal. Returns
  `{:ok, %{evaluated: n, open: n}}`.
  """
  def sweep(today \\ Date.utc_today(), policy \\ ClaimSizing.default_policy()) do
    accounts = sizeable_accounts()

    open =
      accounts
      |> Enum.map(&converge_account(&1, today, policy))
      |> Enum.count(&(&1 == :open))

    {:ok, %{evaluated: length(accounts), open: open}}
  end

  def open_proposal_for(%Account{id: account_id}) do
    Repo.get_by(ClaimProposal, account_id: account_id, status: :open)
  end

  @doc """
  Open proposals, oldest first, capped at `limit`. What the automatic mode
  drains; the cap bounds how much a sweep may resize in one pass so a
  miscalibrated threshold cannot rebuild the fleet in one night.
  """
  def open_proposals(limit) do
    ClaimProposal
    |> where([proposal], proposal.status == :open)
    |> order_by([proposal], asc: proposal.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def dismiss(%ClaimProposal{status: :open} = proposal, resolved_by) do
    proposal
    |> ClaimProposal.resolve_changeset(:dismissed, resolved_by)
    |> Repo.update()
  end

  def dismiss(%ClaimProposal{}, _resolved_by), do: {:error, :not_open}

  defp converge_account(account, today, policy) do
    open = open_proposal_for(account)

    case ClaimSizing.evaluate(context(account, today, policy), policy) do
      :none ->
        if open, do: supersede(open, "sweep")
        :none

      {direction, recommended, evidence} ->
        record(account, open, direction, recommended, evidence)
        :open
    end
  end

  defp context(account, today, policy) do
    governed = governed_region_ids()
    since = Date.add(today, -(policy.shrink_window_days + 1))

    %{
      plan: AccountPolicies.sizing_plan(account),
      current_claim_size: StorageClaims.effective_claim_size(account),
      rollups: account |> StorageRollups.for_account(since) |> Enum.filter(&(&1.region in governed)),
      last_resized_at: PlacerClaims.last_resized_at(account),
      today: today
    }
  end

  defp record(account, open, direction, recommended, evidence) do
    current = StorageClaims.effective_claim_size(account)

    if open && open.direction == direction && open.recommended_claim_size == recommended &&
         open.current_claim_size == current do
      open
      |> Changeset.change(evidence: evidence)
      |> Repo.update!()
    else
      if open, do: supersede(open, "sweep")

      %ClaimProposal{}
      |> ClaimProposal.changeset(%{
        account_id: account.id,
        region: Map.fetch!(evidence, "region"),
        direction: direction,
        current_claim_size: current,
        recommended_claim_size: recommended,
        evidence: evidence
      })
      |> Repo.insert!()
    end
  end

  defp supersede(%ClaimProposal{} = proposal, resolved_by) do
    proposal
    |> ClaimProposal.resolve_changeset(:superseded, resolved_by)
    |> Repo.update!()
  end

  # Accounts with a non-volumeless instance in a storage-governed region and
  # no operator override. Only there does a claim govern disk, and an
  # override means a human already decided.
  defp sizeable_accounts do
    governed = governed_region_ids()

    Server
    |> where([server], server.region in ^governed)
    |> where([server], server.status not in ^Tuist.Kura.volumeless_statuses())
    |> join(:inner, [server], account in Account, on: account.id == server.account_id)
    |> select([server, account], account)
    |> distinct(true)
    |> Repo.all()
    |> Enum.reject(&StorageClaims.override_for/1)
  end

  # Governance is a property of the region's configuration, not of which
  # regions the runtime exposes: an instance row in a storage-governed region
  # is sizeable wherever the control plane runs.
  defp governed_region_ids do
    Regions.all()
    |> Enum.filter(&Regions.storage_governed?/1)
    |> Enum.map(& &1.id)
  end
end
