defmodule Tuist.Kura.Transfers do
  @moduledoc """
  Maintains the transfer clock the archival sweep decides on.

  `Tuist.Kura.Demand` records that a client asked *where* to send cache
  traffic. This records that traffic actually moved. The two are not the same
  account population: `tuist setup cache` installs a LaunchAgent with
  `RunAtLoad`, so an account whose cache daemon starts at every login keeps
  refreshing its resolution clock without anyone building. Sizing the free-tier
  pool from resolution projects several times the instances that move any bytes
  at all, and every one of those instances holds its plan's quota.

  So the lifecycle reads two clocks. Resolution triggers provisioning, because
  it is the only signal an archived account can produce: with no instance there
  is nothing to push a usage rollup. Transfers decide archival, because they
  are the only signal that the instance is worth its quota.

  The source is `kura_usage_events`, the rollups managed nodes push for their
  own traffic, recorded here as they are ingested rather than derived back out
  of ClickHouse on a timer. Either direction counts: a read-only account still
  needs its cache, and a newly provisioned instance's first traffic is uploads,
  so ingress is what covers the cold start. Rollups carrying no bytes do not:
  a client that resolved, connected, and transferred nothing is exactly the
  population this clock exists to separate out.

  Transfers only ever update a lifecycle row, never create one. A transfer
  presupposes an instance, an instance presupposes the provisioning that
  created the row, and inserting here would mean writing a row with no
  resolution clock for provisioning to read.
  """

  import Ecto.Query

  alias Tuist.Kura.AccountRegionLifecycle
  alias Tuist.Repo

  @doc """
  Advances the transfer clock for every account-region in a batch of usage
  rollups, and starts the clock for any row that does not have one yet.

  One statement per region rather than per account: a push carries one node's
  traffic, so a batch is normally a single region, and the whole batch shares
  its most recent window. That overstates an individual account's transfer by
  at most the batch's own span, against a clock read in days.

  Rows are the ingest rows `Tuist.Kura.Usage` builds, so account and region are
  already resolved.
  """
  def record(rows) when is_list(rows) do
    rows
    |> Enum.filter(&transfer?/1)
    |> Enum.group_by(& &1.region)
    |> Enum.reduce(0, fn {region, region_rows}, updated ->
      updated + touch(region, account_ids(region_rows), latest_window(region_rows))
    end)
  end

  @doc """
  Seeds observed transfers onto existing lifecycle rows, keeping the later
  timestamp, and marks their clock as tracked from `tracked_from`.

  Used by the seeding backfill, which reads history out of ClickHouse. Rows are
  `%{account_id:, service_region:, last_transfer_at:}`.
  """
  def seed(rows, %DateTime{} = tracked_from) when is_list(rows) do
    Enum.reduce(rows, 0, fn row, seeded ->
      seeded + seed_row(row, tracked_from)
    end)
  end

  @doc """
  Marks every lifecycle row in `service_regions` as transfer-tracked from
  `tracked_from`, leaving rows that already have a clock alone.

  Separate from `seed/2` because a row with no observed transfer still needs a
  tracking start: without one the sweep can never archive it, and the
  account-regions with no transfer history are precisely the ones the sweep
  exists to reclaim.
  """
  def start_tracking(service_regions, %DateTime{} = tracked_from) when is_list(service_regions) do
    {count, _} =
      Repo.update_all(
        from(l in AccountRegionLifecycle,
          where: l.service_region in ^service_regions,
          where: is_nil(l.transfer_tracking_started_at),
          update: [set: [transfer_tracking_started_at: ^truncate(tracked_from), updated_at: ^now()]]
        ),
        []
      )

    count
  end

  defp seed_row(%{account_id: account_id, service_region: service_region, last_transfer_at: transfer_at}, tracked_from) do
    transfer_at = truncate(transfer_at)

    {count, _} =
      Repo.update_all(
        from(l in AccountRegionLifecycle,
          where: l.account_id == ^account_id,
          where: l.service_region == ^service_region,
          where: is_nil(l.last_transfer_at) or l.last_transfer_at < ^transfer_at,
          update: [
            set: [
              last_transfer_at: ^transfer_at,
              transfer_tracking_started_at:
                fragment("COALESCE(?, ?)", l.transfer_tracking_started_at, ^truncate(tracked_from)),
              updated_at: ^now()
            ]
          ]
        ),
        []
      )

    count
  end

  # A rollup with no bytes in it is a client that connected and moved nothing.
  # Unattributable traffic drops to account id 0 at the ingest boundary and
  # belongs to no account-region.
  defp transfer?(%{bytes: bytes, account_id: account_id, region: region})
       when is_integer(bytes) and is_integer(account_id) do
    bytes > 0 and account_id != 0 and is_binary(region)
  end

  defp transfer?(_row), do: false

  defp account_ids(rows), do: rows |> Enum.map(& &1.account_id) |> Enum.uniq()

  defp latest_window(rows) do
    rows
    |> Enum.map(& &1.window_start)
    |> Enum.max(NaiveDateTime)
    |> DateTime.from_naive!("Etc/UTC")
    |> truncate()
  end

  # `transfer_tracking_started_at` is coalesced rather than set: the clock
  # starting is a fact about the row, and restarting it on every transfer would
  # keep resetting the grace period that makes the sweep's readings safe.
  defp touch(region, account_ids, transferred_at) do
    {count, _} =
      Repo.update_all(
        from(l in AccountRegionLifecycle,
          where: l.service_region == ^region,
          where: l.account_id in ^account_ids,
          update: [
            set: [
              # Postgres `GREATEST` ignores nulls, so this both advances an
              # existing clock and starts a missing one.
              last_transfer_at: fragment("GREATEST(?, ?)", l.last_transfer_at, ^transferred_at),
              transfer_tracking_started_at: fragment("COALESCE(?, ?)", l.transfer_tracking_started_at, ^transferred_at),
              updated_at: ^now()
            ]
          ]
        ),
        []
      )

    count
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
  defp truncate(%DateTime{} = at), do: DateTime.truncate(at, :second)
end
