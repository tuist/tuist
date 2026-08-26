defmodule Tuist.Kura.ClaimProposals do
  @moduledoc """
  Runs the claim sizing sweep and keeps its proposal records: a fresh
  recommendation opens a proposal, a changed one supersedes it, a withdrawn
  one closes it. Applying is `Tuist.Kura.apply_claim_proposal/2`.

  An operator claim override makes an account invisible here, which is the
  per-account off switch.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Billing.Subscription
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.ClaimProposal
  alias Tuist.Kura.ClaimSizing
  alias Tuist.Kura.PlacerClaim
  alias Tuist.Kura.PlacerClaims
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Kura.StorageClaim
  alias Tuist.Kura.StorageClaims
  alias Tuist.Kura.StorageRollup
  alias Tuist.Repo

  @doc """
  Evaluates every sizeable account and converges its proposal. Returns
  `{:ok, %{evaluated: n, open: n}}`.
  """
  def sweep(today \\ Date.utc_today(), policy \\ ClaimSizing.default_policy()) do
    accounts = sizeable_accounts()
    inputs = sweep_inputs(accounts, today, policy)

    open =
      accounts
      |> Enum.map(&converge_account(&1, inputs, today, policy))
      |> Enum.count(&(&1 == :open))

    {:ok, %{evaluated: length(accounts), open: open}}
  end

  @doc """
  The claim sizing measures an account against: what its governed instances
  are pinned at, then the sized claim, then the plan's. The pinned value is
  what the telemetry describes, and it outlives a change to the plan
  constants, so a lowered default cannot make a running instance look smaller
  than it is.
  """
  def measured_claim_size(%Account{id: account_id} = account) do
    pinned =
      [account_id]
      |> pinned_claims()
      |> Map.get(account_id)

    pinned || PlacerClaims.claim_for(account) || StorageClaims.plan_claim_size(account)
  end

  @doc """
  The account's recent sizing decisions, newest first, whatever became of
  them. With applies automatic this is the useful view: an open proposal is
  transient, while the record of what sizing did and on what evidence is what
  answers a question about a resize after the fact.
  """
  def recent_for(%Account{id: account_id}, limit) do
    ClaimProposal
    |> where([proposal], proposal.account_id == ^account_id)
    |> order_by([proposal], desc: proposal.inserted_at)
    |> limit(^limit)
    |> Repo.all()
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

  @doc """
  How many proposals the sweep applied on its own since `datetime`. Operator
  applies are excluded: the budget guards what happens unattended.
  """
  def automatic_applies_since(%DateTime{} = datetime) do
    ClaimProposal
    |> where([proposal], proposal.status == :applied and proposal.resolved_by == "automatic")
    |> where([proposal], proposal.resolved_at >= ^datetime)
    |> Repo.aggregate(:count)
  end

  def dismiss(%ClaimProposal{} = proposal, resolved_by) do
    case resolve_if_open(proposal, :dismissed, resolved_by) do
      {:ok, dismissed} -> {:ok, dismissed}
      :not_open -> {:error, :not_open}
    end
  end

  defp sweep_inputs(accounts, today, policy) do
    account_ids = Enum.map(accounts, & &1.id)
    governed = governed_region_ids()
    since = Date.add(today, -(policy.shrink_window_days + 1))

    rollups =
      StorageRollup
      |> where([rollup], rollup.account_id in ^account_ids)
      |> where([rollup], rollup.date >= ^since and rollup.region in ^governed)
      |> order_by([rollup], asc: rollup.date)
      |> Repo.all()
      |> Enum.group_by(& &1.account_id)

    placer_claims =
      PlacerClaim
      |> where([claim], claim.account_id in ^account_ids)
      |> Repo.all()
      |> Map.new(&{&1.account_id, &1})

    open_proposals =
      ClaimProposal
      |> where([proposal], proposal.account_id in ^account_ids and proposal.status == :open)
      |> Repo.all()
      |> Map.new(&{&1.account_id, &1})

    %{
      rollups: rollups,
      placer_claims: placer_claims,
      open_proposals: open_proposals,
      pinned_claims: pinned_claims(account_ids)
    }
  end

  # Largest, because a baseline under what an instance holds turns a proposed
  # grow into a silent shrink of that instance's volume.
  defp pinned_claims(account_ids) do
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

  defp converge_account(account, inputs, today, policy) do
    open = Map.get(inputs.open_proposals, account.id)
    placer_claim = Map.get(inputs.placer_claims, account.id)

    current =
      Map.get(inputs.pinned_claims, account.id) ||
        (placer_claim && placer_claim.claim_size) ||
        StorageClaims.plan_claim_size(account)

    context = %{
      plan: AccountPolicies.sizing_plan(account),
      current_claim_size: current,
      rollups: Map.get(inputs.rollups, account.id, []),
      last_resized_at: placer_claim && placer_claim.updated_at,
      today: today
    }

    case ClaimSizing.evaluate(context, policy) do
      :none ->
        if open, do: supersede(open, "sweep")
        :none

      {direction, recommended, evidence} ->
        record(account, open, direction, recommended, evidence, current)
        :open
    end
  end

  defp record(account, open, direction, recommended, evidence, current) do
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
    resolve_if_open(proposal, :superseded, resolved_by)
  end

  # The caller's struct can be stale, so resolution is conditional on the row.
  defp resolve_if_open(%ClaimProposal{id: id}, status, resolved_by) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    ClaimProposal
    |> where([proposal], proposal.id == ^id and proposal.status == :open)
    |> select([proposal], proposal)
    |> Repo.update_all(set: [status: status, resolved_at: now, resolved_by: resolved_by, updated_at: now])
    |> case do
      {1, [resolved]} -> {:ok, resolved}
      {0, _none} -> :not_open
    end
  end

  defp sizeable_accounts do
    governed = governed_region_ids()

    accounts =
      Server
      |> where([server], server.region in ^governed)
      |> where([server], server.status not in ^Tuist.Kura.volumeless_statuses())
      |> join(:inner, [server], account in Account, on: account.id == server.account_id)
      |> select([server, account], account)
      |> distinct(true)
      |> Repo.all()
      # `Billing.effective_plan/1` queries per account without this.
      |> Repo.preload(subscriptions: active_subscriptions())

    overridden =
      StorageClaim
      |> where([claim], claim.account_id in ^Enum.map(accounts, & &1.id))
      |> select([claim], claim.account_id)
      |> Repo.all()
      |> MapSet.new()

    Enum.reject(accounts, &MapSet.member?(overridden, &1.id))
  end

  defp active_subscriptions do
    from(subscription in Subscription, where: subscription.status in ["active", "trialing"])
  end

  # Region configuration, not runtime availability: a governed region is
  # sizeable wherever the control plane runs.
  defp governed_region_ids do
    Regions.all()
    |> Enum.filter(&Regions.storage_governed?/1)
    |> Enum.map(& &1.id)
  end
end
