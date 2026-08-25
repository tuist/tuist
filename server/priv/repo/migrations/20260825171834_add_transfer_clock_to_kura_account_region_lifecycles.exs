defmodule Tuist.Repo.Migrations.AddTransferClockToKuraAccountRegionLifecycles do
  @moduledoc """
  Splits the lifecycle's one clock in two: cache-endpoint resolution keeps
  driving provisioning, and archival moves onto the bytes an instance actually
  moved.

  `last_cache_demand_at` cannot decide archival. `tuist setup cache` installs a
  LaunchAgent with `RunAtLoad`, so the cache daemon resolves an endpoint on
  every login, and an account whose agent is installed but idle refreshes that
  timestamp forever without anyone building. `last_transfer_at` is maintained
  from the `kura_usage_events` rollups the instances push for real transfers in
  either direction, which no idle daemon produces.

  `transfer_tracking_started_at` is the guard that makes the switch safe:
  archiving against an unseeded transfer clock would read every provisioned
  instance as unused and reclaim the fleet on the first sweep, so an instance
  is only archivable once its transfer clock has been in place for the
  tracking grace period.

  `unused_archived_at` keeps the loop an identity rather than a cycle. An
  instance archived for moving zero bytes still has a client resolving
  endpoints, and provisioning reads that clock, so without a record of the
  archival the next tick would hand the instance straight back.
  """
  use Ecto.Migration

  def change do
    alter table(:kura_account_region_lifecycles) do
      # Latest window in which the account moved bytes through its instance in
      # this region, either direction. Null means no transfer has been observed
      # since tracking began.
      add :last_transfer_at, :timestamptz

      # When the transfer clock became authoritative for this row, stamped by
      # the seeding backfill and on row creation. Null means it never did, and
      # the sweep refuses to archive on a clock it cannot trust.
      add :transfer_tracking_started_at, :timestamptz

      # When this account-region was last archived for having moved zero bytes
      # through the instance it was given. Holds it out of resolution-driven
      # provisioning for an inactivity window.
      add :unused_archived_at, :timestamptz
    end
  end
end
