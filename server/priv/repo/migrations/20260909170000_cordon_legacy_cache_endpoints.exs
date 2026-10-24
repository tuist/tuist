defmodule Tuist.Repo.Migrations.CordonLegacyCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # A cordon, not a decommission. The boxes stay up and stay in the Kamal fleet,
  # so re-enabling is the whole rollback and `down` performs it. Everything a
  # client is handed comes from CacheEndpoints.list_active_cache_endpoints/0,
  # which filters on enabled, so these leave rotation on the next resolution
  # while clients that resolved in the previous hour keep reaching a live box
  # until their answer expires.
  #
  # Disabled rather than deleted for the same reason as the Vultr endpoints
  # before them: CacheEndpointFormatter reads the whole table, so the row is what
  # renders historical runs under the region's real name and what keeps it in the
  # cache-runs filter. command_events has no TTL, so those runs stay queryable.
  @urls [
    "https://cache-ap-southeast.tuist.dev",
    "https://cache-us-east-2.tuist.dev",
    "https://cache-eu-north.tuist.dev"
  ]

  def up do
    for url <- @urls do
      execute "UPDATE cache_endpoints SET enabled = false, updated_at = NOW() WHERE url = '#{url}'"
    end
  end

  def down do
    for url <- @urls do
      execute "UPDATE cache_endpoints SET enabled = true, updated_at = NOW() WHERE url = '#{url}'"
    end
  end
end
