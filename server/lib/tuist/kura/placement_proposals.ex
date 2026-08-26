defmodule Tuist.Kura.PlacementProposals do
  @moduledoc """
  Runs the placement sweep and keeps its proposal records: a fresh
  recommendation opens a proposal, a changed one supersedes it, a withdrawn
  one closes it. Applying is `Tuist.Kura.apply_placement_proposal/2`.

  An account an operator has pinned is invisible here. The pin is this
  feature's per-account rollback, so it has to mean the placer stops looking
  at the account rather than that its proposals stop being applied.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Tuist.Accounts.Account
  alias Tuist.Billing.Subscription
  alias Tuist.Kura.AccountPolicies
  alias Tuist.Kura.AccountRegionPolicy
  alias Tuist.Kura.OriginRollup
  alias Tuist.Kura.Placement
  alias Tuist.Kura.PlacementProposal
  alias Tuist.Kura.PlacerRegion
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  @doc """
  Evaluates every placeable account and converges its proposal. Returns
  `{:ok, %{evaluated: n, open: n}}`.
  """
  def sweep(today \\ Date.utc_today(), policy \\ Placement.default_policy()) do
    accounts = placeable_accounts()
    inputs = sweep_inputs(accounts, today, policy)

    open =
      accounts
      |> Enum.map(&converge_account(&1, inputs, today, policy))
      |> Enum.count(&(&1 == :open))

    {:ok, %{evaluated: length(accounts), open: open}}
  end

  @doc """
  Where the account is served from right now, as the placer reads it: its
  placement rows when it has them, and otherwise the regions its live
  instances are in.

  The fallback is what lets the sweep evaluate an account the pin-the-present
  backfill has not reached, and it is the same set `serving_regions/1` would
  return once it has.
  """
  def serving_regions(%Account{} = account) do
    fall_back_to_live(account, PlacerRegions.serving_regions(account))
  end

  @doc """
  Every region the account holds, retiring ones included. What an apply checks
  its premises against, so a decision cannot be taken twice about a region
  already on its way out.
  """
  def claimed_regions(%Account{} = account) do
    fall_back_to_live(account, PlacerRegions.claimed_regions(account))
  end

  defp fall_back_to_live(account, []), do: account.id |> List.wrap() |> live_regions() |> Map.get(account.id, [])
  defp fall_back_to_live(_account, regions), do: regions

  def open_proposal_for(%Account{id: account_id}) do
    Repo.get_by(PlacementProposal, account_id: account_id, status: :open)
  end

  @doc """
  Open proposals, oldest first, capped at `limit`. What automatic mode drains;
  the cap bounds how much placement may move in one pass.
  """
  def open_proposals(limit) do
    PlacementProposal
    |> where([proposal], proposal.status == :open)
    |> order_by([proposal], asc: proposal.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  One page of the account's placement decisions, newest first, with the Flop
  meta the pagination component reads.
  """
  def paginate_for(%Account{id: account_id}, options) do
    PlacementProposal
    |> where([proposal], proposal.account_id == ^account_id)
    |> Flop.validate_and_run!(options, for: PlacementProposal)
  end

  @doc """
  The account's recent placement decisions, newest first, whatever became of
  them.
  """
  def recent_for(%Account{id: account_id}, limit) do
    PlacementProposal
    |> where([proposal], proposal.account_id == ^account_id)
    |> order_by([proposal], desc: proposal.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  How many proposals the sweep applied on its own since `datetime`. Operator
  applies are excluded: the budget guards what happens unattended.
  """
  def automatic_applies_since(%DateTime{} = datetime) do
    PlacementProposal
    |> where([proposal], proposal.status == :applied and proposal.resolved_by == "automatic")
    |> where([proposal], proposal.resolved_at >= ^datetime)
    |> Repo.aggregate(:count)
  end

  def dismiss(%PlacementProposal{} = proposal, resolved_by) do
    case resolve_if_open(proposal, :dismissed, resolved_by) do
      {:ok, dismissed} -> {:ok, dismissed}
      :not_open -> {:error, :not_open}
    end
  end

  def supersede(%PlacementProposal{} = proposal, resolved_by) do
    resolve_if_open(proposal, :superseded, resolved_by)
  end

  defp sweep_inputs(accounts, today, policy) do
    account_ids = Enum.map(accounts, & &1.id)
    since = Date.add(today, -(Placement.window_days(policy) + 1))

    rollups =
      OriginRollup
      |> where([rollup], rollup.account_id in ^account_ids and rollup.date >= ^since)
      |> order_by([rollup], asc: rollup.date)
      |> Repo.all()
      |> Enum.group_by(& &1.account_id)

    placer_regions =
      PlacerRegion
      |> where([placer], placer.account_id in ^account_ids)
      |> Repo.all()
      |> Enum.group_by(& &1.account_id)

    open_proposals =
      PlacementProposal
      |> where([proposal], proposal.account_id in ^account_ids and proposal.status == :open)
      |> Repo.all()
      |> Map.new(&{&1.account_id, &1})

    %{
      rollups: rollups,
      placer_regions: placer_regions,
      open_proposals: open_proposals,
      live_regions: live_regions(account_ids),
      instance_ages: instance_ages(account_ids),
      relocations: relocation_counts(account_ids, today, policy)
    }
  end

  # The oldest live instance per account-region, which is how long the account
  # has actually been served from there.
  defp instance_ages(account_ids) do
    Server
    |> where([server], server.account_id in ^account_ids)
    |> where([server], server.region in ^public_region_ids())
    |> where([server], server.status not in ^Tuist.Kura.volumeless_statuses() and server.move_phase == :none)
    |> group_by([server], [server.account_id, server.region])
    |> select([server], {server.account_id, server.region, min(server.inserted_at)})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), fn {_account_id, region, inserted_at} ->
      {region, DateTime.to_date(inserted_at)}
    end)
    |> Map.new(fn {account_id, entries} -> {account_id, Map.new(entries)} end)
  end

  defp converge_account(account, inputs, today, policy) do
    open = Map.get(inputs.open_proposals, account.id)
    plan = AccountPolicies.sizing_plan(account)
    placer_rows = Map.get(inputs.placer_regions, account.id, [])
    live = Map.get(inputs.live_regions, account.id, [])

    context = %{
      plan: plan,
      rollups: Map.get(inputs.rollups, account.id, []),
      permitted: AccountPolicies.placeable_regions(account, plan),
      primary: primary_from(placer_rows, live),
      serving: serving_from(placer_rows, live),
      retiring: for(row <- placer_rows, row.status == :retiring, do: row.region),
      held_since: held_since(placer_rows, Map.get(inputs.instance_ages, account.id, %{})),
      relocations_in_window: Map.get(inputs.relocations, account.id, 0),
      today: today
    }

    case Placement.evaluate(context, policy) do
      :none ->
        if open, do: supersede(open, "sweep")
        :none

      verdict ->
        record(account, open, verdict)
        :open
    end
  end

  defp record(account, open, verdict) do
    attrs = attrs_for(verdict)

    if open && open.kind == attrs.kind && open.from_region == attrs.from_region &&
         open.to_region == attrs.to_region do
      open
      |> Changeset.change(evidence: attrs.evidence)
      |> Repo.update!()
    else
      if open, do: supersede(open, "sweep")

      %PlacementProposal{}
      |> PlacementProposal.changeset(Map.put(attrs, :account_id, account.id))
      |> Repo.insert!()
    end
  end

  defp attrs_for({:relocate, from, to, evidence}),
    do: %{kind: :relocate, from_region: from, to_region: to, evidence: evidence}

  defp attrs_for({:expand, to, evidence}), do: %{kind: :expand, from_region: nil, to_region: to, evidence: evidence}

  defp attrs_for({:retire, from, evidence}), do: %{kind: :retire, from_region: from, to_region: nil, evidence: evidence}

  # The caller's struct can be stale, so resolution is conditional on the row.
  defp resolve_if_open(%PlacementProposal{id: id}, status, resolved_by) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    PlacementProposal
    |> where([proposal], proposal.id == ^id and proposal.status == :open)
    |> select([proposal], proposal)
    |> Repo.update_all(set: [status: status, resolved_at: now, resolved_by: resolved_by, updated_at: now])
    |> case do
      {1, [resolved]} -> {:ok, resolved}
      {0, _none} -> :not_open
    end
  end

  # Accounts with a live public instance, minus the ones an operator pinned.
  defp placeable_accounts do
    pinned =
      AccountRegionPolicy
      |> where([policy], is_nil(policy.superseded_at))
      |> select([policy], policy.account_id)

    Server
    |> where([server], server.region in ^public_region_ids())
    |> where([server], server.status not in ^Tuist.Kura.volumeless_statuses())
    |> where([server], server.account_id not in subquery(pinned))
    |> join(:inner, [server], account in Account, on: account.id == server.account_id)
    |> select([server, account], account)
    |> distinct(true)
    |> Repo.all()
    # `Billing.effective_plan/1` queries per account without this.
    |> Repo.preload(subscriptions: active_subscriptions())
  end

  defp live_regions(account_ids) do
    Server
    |> where([server], server.account_id in ^account_ids)
    |> where([server], server.region in ^public_region_ids())
    |> where([server], server.status not in ^Tuist.Kura.volumeless_statuses() and server.move_phase == :none)
    |> order_by([server], asc: server.inserted_at, asc: server.id)
    |> select([server], {server.account_id, server.region})
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {account_id, regions} -> {account_id, Enum.uniq(regions)} end)
  end

  defp relocation_counts(account_ids, today, policy) do
    since =
      policy
      |> Map.values()
      |> Enum.map(& &1.relocation_window_days)
      |> Enum.max()
      |> then(&Date.add(today, -&1))
      |> DateTime.new!(~T[00:00:00])

    PlacementProposal
    |> where([proposal], proposal.account_id in ^account_ids)
    |> where([proposal], proposal.kind == :relocate and proposal.status == :applied)
    |> where([proposal], proposal.resolved_at >= ^since)
    |> group_by([proposal], proposal.account_id)
    |> select([proposal], {proposal.account_id, count(proposal.id)})
    |> Repo.all()
    |> Map.new()
  end

  # Placement rows are the answer once they exist; live instances are what an
  # account not yet reached by the backfill is read from.
  defp serving_from([], live), do: live
  defp serving_from(rows, _live), do: Enum.map(rows, & &1.region)

  # When the account started holding each region. The placement row is the
  # answer once one exists, and the instance's own age is what an account the
  # backfill never reached is read from.
  defp held_since(placer_rows, instance_ages) do
    Map.merge(instance_ages, Map.new(placer_rows, &{&1.region, DateTime.to_date(&1.inserted_at)}))
  end

  defp primary_from([], live), do: List.first(live)

  defp primary_from(rows, live) do
    case Enum.find(rows, &(&1.role == :primary)) do
      nil -> List.first(live)
      row -> row.region
    end
  end

  defp active_subscriptions do
    from(subscription in Subscription, where: subscription.status in ["active", "trialing"])
  end

  defp public_region_ids do
    Regions.all()
    |> Enum.reject(&Regions.private?/1)
    |> Enum.map(& &1.id)
  end
end
