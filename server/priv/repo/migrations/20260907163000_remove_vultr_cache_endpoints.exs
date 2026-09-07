defmodule Tuist.Repo.Migrations.RemoveVultrCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # The Vultr legacy cache VMs are decommissioned. Clients re-resolve to the
  # nearest remaining enabled endpoint. cache-au-east and cache-us-central were
  # never seeded into this table, so only cache-sa-west needs removing.

  @url "https://cache-sa-west.tuist.dev"

  def up do
    execute "DELETE FROM cache_endpoints WHERE url = '#{@url}'"
  end

  # Irreversible: the machines behind these endpoints are destroyed, so restoring
  # the row would publish an endpoint that resolves to nothing and cost every
  # client a probe timeout during endpoint selection.
  def down, do: :ok
end
