defmodule Tuist.Kura.Workers.ClaimSizingWorker do
  @moduledoc """
  Refreshes the trailing storage rollups, converges the proposal set, and —
  only when the automatic flag is on — applies proposals within a fleet-wide
  budget. Ten-minute cadence: the fastest growth rungs are satisfied by
  evicted volume, which a thrashing account can produce in minutes.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:worker],
      period: :infinity,
      states: :incomplete
    ]

  alias Tuist.FeatureFlags
  alias Tuist.Kura
  alias Tuist.Kura.ClaimProposals
  alias Tuist.Kura.StorageRollups

  # A rate, not a per-pass count, so cadence changes cannot multiply it.
  @max_automatic_applies_per_hour 5

  # Covers the day boundary and at-least-once redelivery of node batches.
  @refresh_trailing_days 2

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    {:ok, _count} = StorageRollups.refresh(Date.add(today, -@refresh_trailing_days), today)
    {:ok, _summary} = ClaimProposals.sweep(today)

    if FeatureFlags.kura_claim_sizing_automatic?() do
      apply_within_budget()
    end

    :ok
  end

  defp apply_within_budget do
    spent =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> ClaimProposals.automatic_applies_since()

    case @max_automatic_applies_per_hour - spent do
      budget when budget > 0 ->
        budget
        |> ClaimProposals.open_proposals()
        |> Enum.each(&Kura.apply_claim_proposal(&1, "automatic"))

      _exhausted ->
        :ok
    end
  end
end
