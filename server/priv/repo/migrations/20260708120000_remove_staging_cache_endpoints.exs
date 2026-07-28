defmodule Tuist.Repo.Migrations.RemoveStagingCacheEndpoints do
  use Ecto.Migration
  # credo:disable-for-this-file ExcellentMigrations.CredoCheck.MigrationsSafety

  # The staging legacy cache VMs (cache-eu-central-staging, cache-us-east-staging)
  # are decommissioned; staging cache traffic is served by the per-account Kura
  # endpoints. Deleting by URL is a no-op in every other environment, including
  # fresh databases where the seed migration recreates the rows before this one
  # removes them.

  @staging_urls [
    "https://cache-eu-central-staging.tuist.dev",
    "https://cache-us-east-staging.tuist.dev"
  ]

  def up do
    for url <- @staging_urls do
      execute "DELETE FROM cache_endpoints WHERE url = '#{url}'"
    end
  end

  def down do
    if Tuist.Environment.tuist_hosted?() and Tuist.Environment.env() == :stag do
      execute seed_sql("https://cache-eu-central-staging.tuist.dev", "EU Central Staging")
      execute seed_sql("https://cache-us-east-staging.tuist.dev", "US East Staging")
    end
  end

  defp seed_sql(url, display_name) do
    now =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_naive()
      |> NaiveDateTime.to_iso8601()

    """
    INSERT INTO cache_endpoints (id, url, display_name, enabled, inserted_at, updated_at)
    VALUES (gen_random_uuid(), '#{url}', '#{display_name}', true, '#{now}', '#{now}')
    """
  end
end
