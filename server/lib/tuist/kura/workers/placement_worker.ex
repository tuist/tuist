defmodule Tuist.Kura.Workers.PlacementWorker do
  @moduledoc """
  Converges the placement proposal set, and applies proposals within a
  fleet-wide daily budget.

  Daily, because every threshold it reads is a span of whole days and the
  shortest is a fortnight. Running it more often would multiply the query
  volume and change nothing about when a region is added or left.

  The budget starts at zero, so the sweep proposes and an operator applies.
  That is the supervised phase the rollout asks for, and raising the budget is
  what graduates placement to automatic — a configuration change rather than a
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

  alias Tuist.Environment
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
  defp apply_within_budget do
    spent =
      DateTime.utc_now()
      |> DateTime.add(-86_400, :second)
      |> PlacementProposals.automatic_applies_since()

    case Environment.kura_placement_automatic_applies_per_day() - spent do
      budget when budget > 0 ->
        budget
        |> PlacementProposals.open_proposals()
        |> Enum.each(&Kura.apply_placement_proposal(&1, "automatic"))

      _exhausted ->
        :ok
    end
  end
end
