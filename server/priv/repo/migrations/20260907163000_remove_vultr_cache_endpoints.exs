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

  def down do
    if Tuist.Environment.tuist_hosted?() and Tuist.Environment.env() == :prod do
      now =
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.to_naive()
        |> NaiveDateTime.to_iso8601()

      execute """
      INSERT INTO cache_endpoints (id, url, display_name, enabled, inserted_at, updated_at)
      VALUES (gen_random_uuid(), '#{@url}', 'South America West', true, '#{now}', '#{now}')
      """
    end
  end
end
