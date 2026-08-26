defmodule Tuist.Kura.Workers.ClaimSizingWorker do
  @moduledoc """
  Claim sizing pass: refreshes the trailing storage rollups from ClickHouse,
  converges the proposal set, and — only when the automatic flag is on —
  applies open proposals within a fleet-wide budget.

  It runs every ten minutes rather than hourly because the fastest rungs of
  the growth ladder are bought with evicted volume rather than elapsed days,
  and an account thrashing badly enough to satisfy one of them can do so in
  minutes. An hourly tick would have made the schedule, not the evidence, the
  thing such an account waited on. The pass itself is cheap at this cadence:
  the refresh is two grouped ClickHouse reads over a short trailing window,
  and the sweep's inputs are set-based queries whose cost tracks the number
  of sizeable accounts rather than the tick rate.
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

  # How much the fleet may resize unattended in an hour. Deliberately a rate
  # rather than a per-pass count: a per-pass cap would silently multiply the
  # blast radius the moment the cadence changed, which is exactly what just
  # happened to this worker.
  @max_automatic_applies_per_hour 5

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
