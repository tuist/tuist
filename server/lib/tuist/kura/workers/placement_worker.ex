defmodule Tuist.Kura.Workers.PlacementWorker do
  @moduledoc """
  Converges the placement proposal set, and applies proposals within a
  fleet-wide daily budget per proposal kind.

  Hourly. Every threshold it reads is a span of whole days, so the cadence
  changes nothing about when a region is added or left; what it changes is how
  stale the open proposals an operator is looking at can be. A pass is a fixed
  handful of set-based queries whatever the account count, so an hour costs
  little and a day would mean deciding from evidence that has moved on.

  Every budget starts at zero, so the sweep proposes and an operator applies.
  That is the supervised phase the rollout asks for, and raising a budget is
  what graduates one kind to automatic — a configuration change rather than a
  code path, so the two phases cannot diverge.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:worker],
      period: :infinity,
      states: :incomplete
    ]

  alias Tuist.Kura
  alias Tuist.Kura.PlacementProposals

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _summary} = PlacementProposals.sweep(Date.utc_today())

    apply_within_budget()

    :ok
  end

  # A rate over a trailing day rather than a per-pass count, so changing the
  # cadence cannot multiply how much the fleet moves. Operator applies do not
  # spend it: the budget guards what happens unattended.
  #
  # Each kind draws on its own budget, so a fleet-wide count cannot be spent by
  # whichever kind happens to sit oldest in the backlog. Two accounts waiting
  # to expand must not be able to hold back the account that is being served
  # from the wrong continent, and neither must be able to spend the allowance
  # that decides how fast warm caches are given up.
  defp apply_within_budget do
    spent =
      DateTime.utc_now()
      |> DateTime.add(-86_400, :second)
      |> PlacementProposals.automatic_applies_since()

    Enum.each(PlacementProposals.automatic_apply_budgets(), fn {kind, allowed} ->
      case allowed - Map.fetch!(spent, kind) do
        budget when budget > 0 ->
          kind
          |> PlacementProposals.open_proposals(budget)
          |> Enum.each(&Kura.apply_placement_proposal(&1, "automatic"))

        _exhausted ->
          :ok
      end
    end)
  end
end
