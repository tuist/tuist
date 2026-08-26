defmodule Tuist.Kura.Workers.ClaimSizingWorker do
  @moduledoc """
  Refreshes the rollups whose telemetry arrived recently, converges the
  proposal set, and applies proposals within a fleet-wide budget. Ten-minute
  cadence: the fastest growth rungs are satisfied by evicted volume, which a
  thrashing account can produce in minutes.
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
  alias Tuist.Kura.ClaimProposals
  alias Tuist.Kura.StorageRollups
  alias Tuist.Kura.StorageTelemetry

  # A rate, not a per-pass count, so cadence changes cannot multiply it.
  @max_automatic_applies_per_hour 5

  # How far back to look for telemetry that has arrived, not for telemetry that
  # happened. A node holds undelivered evictions until the control plane
  # answers, so a recovered batch can be stamped with a day well outside this
  # window and still be picked up, as long as the sweep runs within it. Wide
  # enough to survive the worker itself being down for a day.
  @ingest_lookback_days 2

  # Past the longest policy window no rollup can change a verdict, so there is
  # nothing to gain from recomputing one.
  @refresh_horizon_days 90

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    today = Date.utc_today()
    {:ok, _count} = StorageRollups.refresh(dates_to_refresh(today))
    {:ok, _summary} = ClaimProposals.sweep(today)

    apply_within_budget()

    :ok
  end

  defp dates_to_refresh(today) do
    since =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-@ingest_lookback_days * 86_400)
      |> NaiveDateTime.truncate(:second)

    StorageTelemetry.dates_with_telemetry_ingested_since(
      since,
      Date.add(today, -@refresh_horizon_days),
      today
    )
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
