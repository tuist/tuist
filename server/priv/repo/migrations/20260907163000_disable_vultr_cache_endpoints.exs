defmodule Tuist.Repo.Migrations.DisableVultrCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # The Vultr legacy cache VMs are decommissioned. Clients re-resolve to the
  # nearest remaining enabled endpoint. cache-au-east and cache-us-central were
  # never seeded into this table, so only cache-sa-west needs taking out.
  #
  # Disabled rather than deleted. Everything handed to a client comes from
  # CacheEndpoints.list_active_cache_endpoints/0, which filters on enabled, so
  # the row leaves rotation either way. The rest of the row still has a job:
  # CacheEndpointFormatter reads the whole table, so the row is what renders
  # historical Santiago runs as "South America West" and what puts the endpoint
  # in the cache-runs filter. Deleting it would fall back to the URL formatter,
  # which has no sa-west case and would render "Sa West", and would drop the
  # filter option. command_events has no TTL, so those runs stay queryable.
  @url "https://cache-sa-west.tuist.dev"

  def up do
    execute "UPDATE cache_endpoints SET enabled = false, updated_at = NOW() WHERE url = '#{@url}'"
  end

  # Irreversible: the machines behind the endpoint are destroyed, so re-enabling
  # would publish an endpoint that resolves to nothing and cost every client a
  # probe timeout during endpoint selection.
  def down, do: :ok
end
