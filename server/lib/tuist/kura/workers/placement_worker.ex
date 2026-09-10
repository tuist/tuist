defmodule Tuist.Kura.Workers.PlacementWorker do
  @moduledoc """
  Converges the placement proposal set, and applies the proposals it may.

  Hourly. Every threshold it reads is a span of whole days, so the cadence
  changes nothing about when a region is added or left; what it changes is how
  stale the open proposals an operator is looking at can be. A pass is a fixed
  handful of set-based queries whatever the account count, so an hour costs
  little and a day would mean deciding from evidence that has moved on.

  Every budget starts at zero, so the sweep proposes and an operator applies.
  Raising a budget is what graduates one kind to automatic: a configuration
  change rather than a code path, so the two phases cannot diverge, and zero
  stays the way to stop a kind without a deploy of its own.
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

  # Most kinds have no ceiling here, and drain whatever the sweep left open.
  # What bounds them is the policy, per account: expansion stops at the plan's
  # region count, relocation runs once a quarter, correction fires once in an
  # account's life. Those scale with the fleet because they are asked per
  # account; a fleet-wide count does not, and one sat in front of a queue that
  # grows with the account count only ever falls further behind. It would also
  # do real damage rather than merely delay: a correction expires once the
  # placement it replaces is a fortnight old, so a queue that runs long turns
  # corrections into three-month relocations.
  #
  # A ceiling is kept where a mistake cannot be taken back, which is retirement
  # alone. Per-account limits say nothing about how many accounts move at once,
  # so a rung deciding wrongly for the whole fleet is bounded by nothing else.
  # Sized as a stop rather than a throttle: high enough that it never binds on
  # a real day, low enough that a fleet-wide misfire costs one day's worth of
  # regions instead of all of them.
  #
  # What ceilings remain are a rate over a trailing day rather than a per-pass
  # count, so changing the cadence cannot multiply how much the fleet moves.
  # Operator applies do not spend them: they guard what happens unattended.
  defp apply_within_budget do
    spent =
      DateTime.utc_now()
      |> DateTime.add(-86_400, :second)
      |> PlacementProposals.automatic_applies_since()

    Enum.each(PlacementProposals.automatic_apply_budgets(), fn {kind, allowed} ->
      case remaining(allowed, Map.fetch!(spent, kind)) do
        :unlimited -> apply_open(kind, :unlimited)
        budget when budget > 0 -> apply_open(kind, budget)
        _exhausted -> :ok
      end
    end)
  end

  defp remaining(:unlimited, _spent), do: :unlimited
  defp remaining(allowed, spent), do: allowed - spent

  defp apply_open(kind, limit) do
    kind
    |> PlacementProposals.open_proposals(limit)
    |> Enum.each(&Kura.apply_placement_proposal(&1, "automatic"))
  end
end
