defmodule Tuist.Kura.Workers.BackfillCacheTransfersWorker do
  @moduledoc """
  Seeds the transfer clock on `kura_account_region_lifecycles` from the
  `kura_usage_events` history that predates it.

  Archival reads `last_transfer_at`. Enabling it against an unseeded column
  would read every provisioned instance as having moved zero bytes and archive
  the fleet on the first sweep, so this worker is what stands between those two
  things, the same way `Tuist.Kura.Workers.BackfillCacheDemandWorker` does for
  the resolution clock. Two things make a seeded row safe to act on:

    * an account-region with no `transfer_tracking_started_at` is never
      archived, so a row this worker never reaches stays out of the sweep
      rather than being read as unused, and
    * a clock younger than `TUIST_KURA_DEMAND_TRACKING_GRACE_DAYS` is never
      archived either, so the live ingest hook has a full window to correct
      anything the history missed before any row can be acted on.

  Every lifecycle row in a public region has its clock started, not only the
  ones with observed transfers. An account-region with no usage event in the
  lookback is exactly the population the sweep exists to reclaim, and leaving
  it untracked would put it permanently out of reach.

  Seeding only. The steady-state mechanism is the ingest boundary
  (`Tuist.Kura.Transfers`), which is why this is a manually enqueued one-off
  rather than a cron.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Tuist.ClickHouseRepo
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Transfers

  require Logger

  # Wider than the 90-day inactivity window on purpose. An instance whose last
  # transfer predates the window is archived either way, but only a seeded
  # timestamp tells the sweep it is inactive rather than never used, and the
  # two archive on different terms.
  @default_lookback_days 365

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    lookback_days = Map.get(args, "lookback_days", @default_lookback_days)

    tracked_from = DateTime.truncate(DateTime.utc_now(), :second)

    since =
      tracked_from
      |> DateTime.add(-lookback_days * 86_400, :second)
      |> DateTime.truncate(:second)

    case lifecycle_region_ids() do
      [] ->
        :ok

      region_ids ->
        seeded = Transfers.seed(observed_transfers(since, region_ids), tracked_from)
        tracked = Transfers.start_tracking(region_ids, tracked_from)

        Logger.info(
          "[Kura.BackfillCacheTransfers] seeded #{seeded} observed transfer timestamps over #{lookback_days} days and started tracking on #{tracked} untracked account-regions"
        )

        :ok
    end
  end

  defp lifecycle_region_ids do
    Regions.available()
    |> Enum.reject(&Regions.private?/1)
    |> Enum.map(& &1.id)
  end

  # Bytes in either direction: a read-only account still needs its cache, and a
  # newly provisioned instance's first traffic is uploads. Rollups carrying no
  # bytes are the population this clock exists to separate out, so they do not
  # count as a transfer.
  defp observed_transfers(since, region_ids) do
    """
    SELECT account_id, region, max(window_start)
    FROM kura_usage_events
    WHERE window_start >= {since:DateTime}
      AND account_id != 0
      AND bytes > 0
      AND region IN {regions:Array(String)}
    GROUP BY account_id, region
    """
    |> ClickHouseRepo.query!(%{"since" => DateTime.to_naive(since), "regions" => region_ids})
    |> Map.fetch!(:rows)
    |> Enum.map(fn [account_id, region, transfer_at] ->
      %{account_id: account_id, service_region: region, last_transfer_at: to_utc(transfer_at)}
    end)
  end

  defp to_utc(%DateTime{} = at), do: DateTime.truncate(at, :second)

  defp to_utc(%NaiveDateTime{} = at) do
    at |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
  end
end
