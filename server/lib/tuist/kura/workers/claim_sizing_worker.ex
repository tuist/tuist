defmodule Tuist.Kura.Workers.ClaimSizingWorker do
  @moduledoc """
  Hourly claim sizing pass: refreshes the trailing storage rollups from
  ClickHouse, converges the proposal set, and — only when the automatic flag
  is on — applies a bounded number of open proposals.

  Hourly rather than daily so the ops surface tracks today's telemetry as it
  accumulates; the policy windows are measured in days, so the cadence adds
  freshness, not churn.
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

  # How much one pass may resize with nobody watching. A miscalibrated
  # threshold then moves at most this many accounts before the next human
  # look, instead of the fleet in one night.
  @max_automatic_applies_per_pass 5

  # The trailing refresh window. Two days cover the day boundary and
  # at-least-once redelivery of node batches; older days are immutable once
  # their events' delivery settled.
  @refresh_trailing_days 2

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    {:ok, _count} = StorageRollups.refresh(Date.add(today, -@refresh_trailing_days), today)
    {:ok, _summary} = ClaimProposals.sweep(today)

    if FeatureFlags.kura_claim_sizing_automatic?() do
      @max_automatic_applies_per_pass
      |> ClaimProposals.open_proposals()
      |> Enum.each(&Kura.apply_claim_proposal(&1, "automatic"))
    end

    :ok
  end
end
